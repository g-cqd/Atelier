import AemiRuntime
import AppKit
import AtelierDiagnostics
import AtelierLSP
import AtelierProcess
import DiffComparison
import DiffCore
import DiffGit
import DiffRendering
import DiffTextKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@main
struct GitDiffViewerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var settings: ViewerSettings
    @State private var recents = RecentComparisons()
    /// Keeps `NSApp.appearance` in sync with `settings.appearanceScheme` for the app's whole life -- see
    /// ``AppearanceApplier``. Held as `@State` purely so one instance survives every `body` re-evaluation instead
    /// of being rebuilt (and re-subscribed) on each one; nothing here ever reads it back.
    @State private var appearanceApplier: AppearanceApplier

    init() {
        let settings = ViewerSettings()
        _settings = State(initialValue: settings)
        _appearanceApplier = State(initialValue: AppearanceApplier(settings: settings))
    }

    var body: some Scene {
        // First, so a click on the Dock icon with no window open brings the welcome back. A launch with paths on
        // the command line skips it and opens the comparison straight away.
        Window("Welcome to Git Diff Viewer", id: WindowID.welcome) {
            WelcomeView(recents: recents, reader: appDelegate.services.loader)
                // Explicitly opted out, not just left at the `.automatic` default: AppKit's automatic grouping
                // can still merge windows that share a class and toolbar configuration, and the welcome window
                // must never join the comparison windows' tab group.
                .background(
                    WindowTabbingConfigurator { window in window.tabbingMode = .disallowed }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                )
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(LaunchOptions.hasArguments ? .suppressed : .presented)
        .restorationBehavior(.disabled)
        .commands {
            CommandGroup(replacing: .newItem) {
                OpenPatchCommand()
                WelcomeCommand()
            }
            SidebarCommands()
        }

        WindowGroup(id: WindowID.comparison, for: LaunchConfiguration.self) { $configuration in
            ComparisonWindow(
                configuration: configuration ?? LaunchOptions.configuration, recents: recents,
                reader: appDelegate.services.loader, services: appDelegate.services
            )
            .frame(minWidth: 900, minHeight: 600)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1400, height: 900)
        .defaultLaunchBehavior(LaunchOptions.hasArguments ? .presented : .suppressed)
        // Not restored: the welcome window's recents are the way back, and restoring would open both.
        .restorationBehavior(.disabled)

        Settings {
            SettingsView(
                settings: settings, runner: appDelegate.services.runner,
                discovery: appDelegate.services.toolDiscovery
            )
        }
    }
}

/// Command-line options. Paths are passed as `-key value` pairs because AppKit opens positional arguments as
/// documents, which makes SwiftUI skip the main window.
enum LaunchOptions {
    static var left: URL? { url(forKey: "left") }
    static var right: URL? { url(forKey: "right") }
    static var repository: URL? { url(forKey: "repo") }
    static var patch: URL? { url(forKey: "patch") }

    /// Whether the command line names something to compare, in which case the welcome window stays out of the way.
    static var hasArguments: Bool {
        patch != nil || (left != nil && right != nil) || repository != nil || leftRef != nil || rightRef != nil
    }

    static var configuration: LaunchConfiguration {
        if let patch { return .patch(patch) }
        if let left, let right { return .files(left: left, right: right) }
        let repository =
            self.repository ?? URL(filePath: FileManager.default.currentDirectoryPath, directoryHint: .isDirectory)
        return .repository(repository, leftRef: leftRef ?? "HEAD", rightRef: rightRef)
    }
    static var leftRef: String? { UserDefaults.standard.string(forKey: "leftRef") }
    static var rightRef: String? { UserDefaults.standard.string(forKey: "rightRef") }

    private static func url(forKey key: String) -> URL? {
        guard let path = UserDefaults.standard.string(forKey: key) else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return nil }
        return URL(filePath: path, directoryHint: isDirectory.boolValue ? .isDirectory : .notDirectory)
    }
}

/// Applies ``ViewerSettings/appearanceScheme`` to `NSApp.appearance`, application-wide rather than per window: a
/// pinned choice describes how the whole app's chrome should look, the same as the theme or the layout chrome
/// already do, not a property of any one comparison window. Reads and observes the app's one shared
/// ``ViewerSettings`` instance -- the same instance the Settings scene edits -- so a change made there takes
/// effect at once, everywhere; every window's own hover panel already matches its own view's
/// `effectiveAppearance` (`HoverDocPanel`), which AppKit derives from this override on its own, so there is
/// nothing to double up there.
@MainActor
private final class AppearanceApplier {
    private let settings: ViewerSettings

    init(settings: ViewerSettings) {
        self.settings = settings
        apply()
        settings.addObserver(self) { [weak self] change in
            guard change == .appearance else { return }
            self?.apply()
        }
    }

    private func apply() {
        // `NSApplication.shared`, not the `NSApp` global: this runs from `GitDiffViewerApp.init()`, before
        // SwiftUI has brought AppKit up, and `NSApp` -- an implicitly-unwrapped optional -- is still nil there.
        // `.shared` creates the application object on first touch, so the launch-time apply is safe and every
        // later one hits the same instance `NSApp` will point at.
        NSApplication.shared.appearance = settings.appearanceScheme.nsAppearance
    }
}

extension AppearanceScheme {
    /// `nil` (the system default) for `.system`: AppKit already treats a `nil` override as "follow the system",
    /// the same thing turning a pinned choice back off should leave behind.
    fileprivate var nsAppearance: NSAppearance? {
        switch self {
            case .system: nil
            case .light: NSAppearance(named: .aqua)
            case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// What the app owns for its whole life and every window shares: the pool git runs on and the loader over it.
final class AppServices {
    /// Four threads: enough for the batch reads a large selection runs side by side, further runs queue.
    let pool = BlockingOffloadPool(width: 4)
    let runner: HardenedProcessRunner
    let loader: SourceLoader

    /// A pool of its own: a slow corpus lint must never starve git's width-4 pool.
    let diagnosticsPool = BlockingOffloadPool(width: 2)
    let diagnosticsRunner: HardenedProcessRunner
    let toolDiscovery: ToolDiscovery
    let diagnosticsEngine: DiagnosticsEngine
    /// One sourcekit-lsp session per workspace root, shared by every comparison window.
    let lspRegistry: SourceKitLSPRegistry

    init() {
        runner = HardenedProcessRunner(pool: pool)
        loader = SourceLoader(runner: runner)

        diagnosticsRunner = HardenedProcessRunner(pool: diagnosticsPool)
        toolDiscovery = ToolDiscovery(
            runner: diagnosticsRunner,
            bundledDirectory: Bundle.main.bundleURL.appending(path: "Contents/Helpers")
        )
        diagnosticsEngine = DiagnosticsEngine(runner: diagnosticsRunner, discovery: toolDiscovery)

        let toolDiscovery = toolDiscovery
        lspRegistry = SourceKitLSPRegistry { root in
            await Self.sourceKitLSPConfiguration(workspaceRoot: root, toolDiscovery: toolDiscovery)
        }
    }

    /// The scratch sourcekit-lsp session behind the SDK documentation tier, kept so termination can drain it
    /// alongside the per-root registry. Double-optional: `.some(nil)` records that resolution already failed,
    /// so a machine without sourcekit-lsp pays the lookup once, not per window.
    private var sdkHoverState: SDKDocumentationProvider??
    private(set) var sdkScratchService: SourceKitLSPService?

    /// The on-device Apple SDK documentation tier, built lazily over the same discovery path as the per-root
    /// language servers and shared by every window.
    func sdkHoverProvider() async -> SDKDocumentationProvider? {
        if let resolved = sdkHoverState { return resolved }
        let location = Self.sourceKitLSPToolLocation()
        guard
            sourceKitLSPDiscoveryEnabled(location),
            let located = await toolDiscovery.locate(
                executableName: "sourcekit-lsp", overrideVariable: "GDV_SOURCEKIT_LSP",
                customPath: location?.customPath, searchesToolchain: true)
        else {
            sdkHoverState = .some(nil)
            return nil
        }
        let service = SDKDocumentationProvider.makeScratchService(serverExecutable: located.url)
        sdkScratchService = service
        let provider = SDKDocumentationProvider(service: service)
        sdkHoverState = provider
        return provider
    }

    func shutdown() {
        pool.shutdown()
        diagnosticsPool.shutdown()
    }

    /// Resolves sourcekit-lsp the same way every other tool is discovered, honoring a user-pinned custom path.
    /// `AppServices` is created before ``ViewerSettings`` (which is per-window, `@State` in the app's scene), so
    /// rather than wire a settings reference through app init, the pinned path is read straight out of user
    /// defaults under the same key ``ViewerSettings`` itself stores `lspServerLocations` under -- this closure
    /// only runs lazily, the first time a workspace root's session is requested, by which point Settings may
    /// well have written a pin.
    private static func sourceKitLSPConfiguration(workspaceRoot: URL, toolDiscovery: ToolDiscovery) async
        -> SourceKitLSPService.Configuration?
    {
        let location = sourceKitLSPToolLocation()
        guard
            sourceKitLSPDiscoveryEnabled(location),
            let located = await toolDiscovery.locate(
                executableName: "sourcekit-lsp", overrideVariable: "GDV_SOURCEKIT_LSP",
                customPath: location?.customPath, searchesToolchain: true)
        else { return nil }
        return SourceKitLSPService.Configuration(serverExecutable: located.url, workspaceRoot: workspaceRoot)
    }

    /// Mirrors ``ViewerSettings/Key/lspServerLocations``'s own user-defaults key: the literal is duplicated
    /// rather than shared because that key lives on a type this app-wide, pre-settings service has no business
    /// depending on. Disabling sourcekit-lsp must gate discovery itself, not merely fall back to searching for it
    /// with no custom path (which workspace and SDK-tier discovery would still happily find on `$PATH` or the
    /// active toolchain) -- so callers check ``ToolLocation/isEnabled`` before ever calling ``ToolDiscovery/locate``.
    private static func sourceKitLSPToolLocation() -> ToolLocation? {
        guard let data = UserDefaults.standard.data(forKey: "lspServerLocations"),
            let decoded = try? JSONDecoder().decode([String: ToolLocation].self, from: data)
        else { return nil }
        return decoded["sourcekit-lsp"]
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let services = AppServices()

    /// Defers termination rather than blocking the MainActor on the drain: `applicationWillTerminate` runs
    /// synchronously on the main thread, and a `DispatchSemaphore.wait` there would freeze the run loop, so any
    /// MainActor hop the drain (or something it calls transitively) ever needs can never happen -- the wait
    /// exhausts its whole budget on every quit instead of returning as soon as the drain finishes. Returning
    /// `.terminateLater` and replying once the drain (or its own bounded timeout) completes keeps the run loop
    /// alive throughout.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { @MainActor in
            await Self.drainLSPSessions(services.lspRegistry, scratch: services.sdkScratchService)
            services.shutdown()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// Best-effort graceful shutdown of every sourcekit-lsp session, bounded so a hung server can never hold
    /// termination up: the graceful `shutdown`/`exit` conversation (itself already timeout-bounded per session)
    /// races a fixed budget, and whatever is still running past it is abandoned -- the process exiting closes
    /// every child's pipes right behind it, which is sourcekit-lsp's own cue to go away.
    private static func drainLSPSessions(_ registry: SourceKitLSPRegistry, scratch: SourceKitLSPService?) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await registry.shutdownAll()
                await scratch?.shutdown()
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(1))
            }
            await group.next()
            group.cancelAll()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowWillClose(_:)), name: NSWindow.willCloseNotification, object: nil)
    }

    /// Closing the last comparison brings the welcome window back instead of quitting, as Xcode does.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// The tab bar's "+" button: AppKit sends this `@IBAction`-style message up the responder chain, which for a
    /// window with no document and no view claiming it falls through to `NSApp`, and from there to its delegate
    /// -- this method is that fallback. Reopening Welcome, rather than launching a blank comparison, is the
    /// existing way this app starts something new (`WelcomeCommand`, and `windowWillClose` below after the last
    /// comparison closes), so the tab bar's plus button follows the same path instead of inventing another one.
    @objc func newWindowForTab(_ sender: Any?) {
        Self.performWelcomeCommand()
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, Self.isComparison(window) else { return }
        let remaining = NSApp.windows.filter { $0 !== window && $0.isVisible && Self.isComparison($0) }
        guard remaining.isEmpty else { return }
        // Through the menu item, which outlives every window, and on the next turn: opened while the close is
        // still under way, SwiftUI presents the closing window again.
        Task { @MainActor in Self.performWelcomeCommand() }
    }

    private static func performWelcomeCommand() {
        for menu in (NSApp.mainMenu?.items ?? []).compactMap(\.submenu) {
            if let index = menu.items.firstIndex(where: { $0.title == WelcomeCommand.title }) {
                menu.performActionForItem(at: index)
                return
            }
        }
    }

    private static func isComparison(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue.hasPrefix(WindowID.comparison) == true
    }
}

/// File ▸ Open Patch… opens the patch in a window of its own.
private struct OpenPatchCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Patch…") {
            if let url = PatchOpenPanel.choose() { openWindow(value: LaunchConfiguration.patch(url)) }
        }
        .keyboardShortcut("o")
    }
}

/// File ▸ Welcome to Git Diff Viewer, the way Xcode brings its welcome window back.
struct WelcomeCommand: View {
    static let title = "Welcome to Git Diff Viewer"
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(Self.title) { openWindow(id: WindowID.welcome) }
            .keyboardShortcut("1", modifiers: [.shift, .command])
    }
}

enum PatchOpenPanel {
    static let contentTypes: [UTType] = [
        UTType(filenameExtension: "patch"), UTType(filenameExtension: "diff"), .plainText
    ]
    .compactMap { $0 }

    static func choose() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = contentTypes
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a unified diff or git patch"
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func isPatch(_ url: URL) -> Bool {
        ["patch", "diff"].contains(url.pathExtension.lowercased())
    }
}

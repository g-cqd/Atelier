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
    /// Keeps the app's appearance in sync with the settings; `@State` so one instance outlives every `body` pass.
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
                // Disallowed outright: automatic tabbing could still merge it into the comparisons' tab group.
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
            .repositoryTrustPrompt(appDelegate.services.repositoryTrust)
            .environment(appDelegate.services.repositoryTrust)
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
            .environment(appDelegate.services.repositoryTrust)
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

/// Applies the shared ``ViewerSettings``' appearance app-wide, following ``AppearancePrecedence``. A palette change
/// re-applies it too, since a theme-matched appearance follows the theme's background.
@MainActor
private final class AppearanceApplier {
    private let settings: ViewerSettings

    init(settings: ViewerSettings) {
        self.settings = settings
        apply()
        settings.addObserver(self) { [weak self] change in
            guard change == .appearance || change == .palette else { return }
            self?.apply()
        }
    }

    private func apply() {
        // `NSApplication.shared`: the first apply runs from the app's `init`, while the `NSApp` global is still nil.
        NSApplication.shared.appearance = Self.resolvedAppearance(
            explicit: settings.appearanceScheme, matchesTheme: settings.matchesThemeAppearance,
            themeLuminance: settings.themePath.flatMap(XcodeThemeLibrary.theme(at:))?.backgroundLuminance)
    }

    /// The override for `NSApplication.appearance`, or nil to follow the system; a `themeLuminance` below
    /// ``AppearancePrecedence/darkLuminanceThreshold`` reads as a dark theme.
    static func resolvedAppearance(
        explicit: AppearanceScheme, matchesTheme: Bool, themeLuminance: Double?
    ) -> NSAppearance? {
        let themeIsDark = themeLuminance.map { $0 < AppearancePrecedence.darkLuminanceThreshold }
        let resolved = AppearancePrecedence.resolve(
            explicit: explicit, matchesTheme: matchesTheme, themeIsDark: themeIsDark)
        return resolved.nsAppearance
    }
}

extension AppearanceScheme {
    /// The appearance to pin, or nil for `.system`, which AppKit reads as following the system.
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
    /// Four threads for git runs and the loader's file reads and hashing: enough for the batch reads a large
    /// selection runs side by side, further runs queue.
    let pool = BlockingOffloadPool(width: 4)
    /// Git's runs, which quitting interrupts before the pool shuts down.
    let runner: InterruptibleProcessRunner
    let loader: SourceLoader

    /// A pool of its own: a slow corpus lint must never starve git's width-4 pool.
    let diagnosticsPool = BlockingOffloadPool(width: 2)
    /// The analyzers' runs, which quitting interrupts first.
    let diagnosticsRunner: InterruptibleProcessRunner
    let toolDiscovery: ToolDiscovery
    let diagnosticsEngine: DiagnosticsEngine
    /// The user's trust decision per repository, which gates sourcekit-lsp there.
    let repositoryTrust = RepositoryTrust()
    /// Whether and how sourcekit-lsp launches, per repository and for the SDK tier.
    let languageServerPolicy: LanguageServerPolicy
    /// One sourcekit-lsp session per trusted workspace root, shared by every comparison window.
    let lspRegistry: LanguageServerRegistry
    /// The on-device Apple SDK documentation tier, resolved once and shared by every comparison window.
    let sdkHoverTier: SDKHoverTier

    init() {
        runner = InterruptibleProcessRunner(base: HardenedProcessRunner(pool: pool))
        loader = SourceLoader(runner: runner, pool: pool)

        diagnosticsRunner = InterruptibleProcessRunner(base: HardenedProcessRunner(pool: diagnosticsPool))
        toolDiscovery = ToolDiscovery(
            runner: diagnosticsRunner,
            bundledDirectory: Bundle.main.bundleURL.appending(path: "Contents/Helpers")
        )
        diagnosticsEngine = DiagnosticsEngine(runner: diagnosticsRunner, discovery: toolDiscovery)

        let policy = LanguageServerPolicy(
            trust: repositoryTrust, locate: LanguageServerPolicy.locate(with: toolDiscovery))
        languageServerPolicy = policy
        let registry = LanguageServerRegistry(
            admits: { root, server in
                guard server == .sourceKitLSP else { return false }
                return await policy.admitsSession(at: root)
            },
            makeConfiguration: { root, server in
                guard server == .sourceKitLSP else { return nil }
                return await policy.configuration(forRoot: root)
            })
        lspRegistry = registry
        policy.stopSessionsOnRevocation(in: registry)
        let sdkRunner = diagnosticsRunner
        sdkHoverTier = SDKHoverTier {
            await policy.resolveSDKTier { platform in await SDKLocation.locate(platform, runner: sdkRunner) }
        }
    }

    /// The SDK tier's provider, which windows hover through; nil when sourcekit-lsp is off app-wide or missing.
    func sdkHoverProvider() async -> SDKDocumentationProvider? {
        await sdkHoverTier.provider()
    }

    /// How the app quits: diagnostics and git work stop first, then the language servers drain while both pools shut
    /// down, all within two seconds.
    func shutdownSequence() -> ShutdownSequence {
        let (runner, diagnosticsRunner, pool, diagnosticsPool) = (runner, diagnosticsRunner, pool, diagnosticsPool)
        let (registry, sdkHoverTier) = (lspRegistry, sdkHoverTier)
        return ShutdownSequence(
            interruptDiagnostics: { diagnosticsRunner.interruptAll() },
            interruptGitWork: { runner.interruptAll() },
            drainLanguageServers: {
                await registry.shutdownAll()
                await sdkHoverTier.shutdown()
            },
            shutdownPools: {
                diagnosticsPool.shutdown()
                pool.shutdown()
            })
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let services = AppServices()

    /// Terminates later, once the shutdown sequence ends or runs out of time: blocking the main thread instead would
    /// stall every main-actor hop the sequence needs, and a pool job that never returns would hold the quit forever.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let sequence = services.shutdownSequence()
        Task { @MainActor in
            let outcome = await sequence.run()
            if outcome == .timedOut { PhaseTrace.log("quitting before every shutdown step finished") }
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
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

    /// The tab bar's "+" button, which reaches the delegate through the responder chain: it opens the welcome
    /// window, the app's one way to start a new comparison.
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

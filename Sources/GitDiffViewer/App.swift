import AppKit
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
    @State private var settings = ViewerSettings()
    @State private var recents = RecentComparisons()

    var body: some Scene {
        // First, so a click on the Dock icon with no window open brings the welcome back. A launch with paths on
        // the command line skips it and opens the comparison straight away.
        Window("Welcome to Git Diff Viewer", id: WindowID.welcome) {
            WelcomeView(recents: recents)
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
            ComparisonWindow(configuration: configuration ?? LaunchOptions.configuration, settings: settings, recents: recents)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1400, height: 900)
        .defaultLaunchBehavior(LaunchOptions.hasArguments ? .presented : .suppressed)
        // Not restored: the welcome window's recents are the way back, and restoring would open both.
        .restorationBehavior(.disabled)

        Settings {
            SettingsView(settings: settings)
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
        let repository = self.repository ?? URL(filePath: FileManager.default.currentDirectoryPath, directoryHint: .isDirectory)
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

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NotificationCenter.default.addObserver(self, selector: #selector(windowWillClose(_:)), name: NSWindow.willCloseNotification, object: nil)
    }

    /// Closing the last comparison brings the welcome window back instead of quitting, as Xcode does.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, Self.isComparison(window) else { return }
        let remaining = NSApp.windows.filter { $0 !== window && $0.isVisible && Self.isComparison($0) }
        guard remaining.isEmpty else { return }
        // Through the menu item, which outlives every window, and on the next turn: opened while the close is
        // still under way, SwiftUI presents the closing window again.
        DispatchQueue.main.async { Self.performWelcomeCommand() }
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
    static let contentTypes: [UTType] = [UTType(filenameExtension: "patch"), UTType(filenameExtension: "diff"), .plainText].compactMap { $0 }

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

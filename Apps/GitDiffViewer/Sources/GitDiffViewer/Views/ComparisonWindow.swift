import AppKit
import DiffComparison
import DiffCore
import DiffGit
import DiffRendering
import DiffTextKit
import Foundation
import SwiftUI

/// One comparison window: owns the model for its configuration, titles the window after what it compares,
/// and keeps the recents up to date as the sides change.
struct ComparisonWindow: View {
    let configuration: LaunchConfiguration
    let recents: RecentComparisons
    let reader: any SourceReading
    let services: AppServices
    /// This window's own settings over the shared defaults, so it can adopt a project without affecting any other
    /// window.
    @State private var settings: ViewerSettings
    /// Built in `init`, not `onAppear`, so the customizable toolbar exists on the first body pass: a toolbar
    /// installed later restores its saved arrangement over the wrong default items.
    @State private var model: DiffViewerModel
    /// Guards the one-time startup work, so a repeated `onAppear` never restarts the comparison.
    @State private var hasStarted = false
    @Environment(\.dismissWindow) private var dismissWindow

    init(
        configuration: LaunchConfiguration, recents: RecentComparisons, reader: any SourceReading,
        services: AppServices
    ) {
        self.configuration = configuration
        self.recents = recents
        self.reader = reader
        self.services = services
        let windowSettings = ViewerSettings()
        _settings = State(initialValue: windowSettings)
        _model = State(
            initialValue: DiffViewerModel(
                settings: windowSettings, reader: reader, history: CommitHistory(runner: services.runner)))
    }

    var body: some View {
        ContentView(settings: settings, model: model)
            .navigationTitle(model.windowTitle)
            .background(
                WindowTabbingConfigurator { window in
                    window.tabbingMode = .preferred
                    window.tabbingIdentifier = WindowID.comparisonTabGroup
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            )
            .onChange(of: model.currentConfiguration) { _, current in
                if let current { recents.record(current) }
            }
            // Follows the comparison's repository, which the source toolbar can switch after launch.
            .onChange(of: model.currentProjectRoot, initial: true) { _, root in
                guard let root else { return }
                settings.adoptProject(ProjectIdentity(root: root))
            }
            .onAppear {
                guard !hasStarted else { return }
                hasStarted = true
                model.attachDiagnostics(engine: services.diagnosticsEngine, settings: settings)
                model.attachSideAnalysis(trust: services.repositoryTrust, runner: services.runner)
                model.attachHoverDocs(lspRegistry: services.lspRegistry)
                model.attachFreshness()
                model.start(configuration)
                recents.record(configuration)
                dismissWindow(id: WindowID.welcome)
            }
            .task {
                model.hoverDocs?.sdkProvider = await services.sdkHoverProvider()
            }
    }
}

enum WindowID {
    static let welcome = "welcome"
    static let comparison = "comparison"
    /// The `NSWindow.tabbingIdentifier` every comparison window shares, a patch's included.
    static let comparisonTabGroup = "comparison-group"
}

/// Runs `configure` on the hosting `NSWindow` once AppKit attaches this view, for the window tabbing settings
/// SwiftUI does not expose.
struct WindowTabbingConfigurator: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ConfiguringView()
        view.configure = configure
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ConfiguringView: NSView {
        var configure: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            configure?(window)
        }

        // Only observes its window, so it never takes events.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

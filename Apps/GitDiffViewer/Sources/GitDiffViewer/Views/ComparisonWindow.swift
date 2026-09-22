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
    /// This window's own settings, not the Settings scene's shared instance: a fresh `ViewerSettings` reads the
    /// exact same base defaults on construction, so the window starts identical to every other one, but from here
    /// on it can adopt a project of its own (below) without perturbing any other open window or the Settings
    /// window editing the app-wide base. A base-default edit made in the Settings window afterward still reaches
    /// this instance's unoverridden keys without a reopen -- see `ViewerSettings.baseSettingChangedNotification`
    /// and `adoptProject`'s own doc comment.
    @State private var settings: ViewerSettings
    /// Built eagerly, not lazily in `onAppear`: `DiffViewerModel.init` does no I/O of its own (that is `start(_:)`,
    /// guarded below by `hasStarted`), so constructing it here costs nothing but gets `ContentView` -- and with it
    /// the window's customizable toolbar -- on screen the very first time this view's body runs. Materializing it
    /// a turn later, once `onAppear` fires, let NSToolbar install itself against a default item set before our
    /// customization existed, so it restored a saved arrangement over the wrong defaults.
    @State private var model: DiffViewerModel
    /// Guards the one-time startup work below: this view's body can run again (e.g. the window losing and
    /// regaining a reason to redraw) without restarting the comparison or re-recording it in the recents.
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
        // Same defaults suite as the Settings scene's instance, so the window opens with identical values; only
        // its identity (this `@State` box) is its own, which is what lets `adoptProject` scope its writes without
        // touching the base the Settings window edits.
        let windowSettings = ViewerSettings()
        _settings = State(initialValue: windowSettings)
        _model = State(initialValue: DiffViewerModel(settings: windowSettings, reader: reader))
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
            // Rebinds the window's project-scoped settings whenever the comparison's own repository changes,
            // not just once at launch: switching to a different repository through the source toolbar must move
            // this window's project-scoped writes with it, or they keep landing under whatever project it
            // launched with. `currentProjectRoot` is already resolved (each side's `SideState.repository` did
            // that work as it loaded, the same way `GitClient.repositoryRoot(containing:)` would), so adopting it
            // needs no further I/O and so no supersession guard of its own -- `onChange` already delivers values
            // in order, and `adoptProject` is synchronous.
            .onChange(of: model.currentProjectRoot, initial: true) { _, root in
                guard let root else { return }
                settings.adoptProject(ProjectIdentity(root: root))
            }
            .onAppear {
                guard !hasStarted else { return }
                hasStarted = true
                // Wired for every comparison window, a patch's included: with no working-tree root the engine
                // simply has nothing to run, so diagnostics stay idle rather than needing a special case here.
                model.attachDiagnostics(engine: services.diagnosticsEngine, settings: settings)
                model.attachHoverDocs(lspRegistry: services.lspRegistry)
                model.attachFreshness()
                model.start(configuration)
                recents.record(configuration)
                dismissWindow(id: WindowID.welcome)
            }
            .task {
                // The SDK documentation tier resolves once per app and slots in behind the doc-comment index;
                // a machine without sourcekit-lsp simply leaves the tier absent.
                model.hoverDocs?.sdkProvider = await services.sdkHoverProvider()
            }
    }
}

enum WindowID {
    static let welcome = "welcome"
    static let comparison = "comparison"
    /// Shared `NSWindow.tabbingIdentifier` for every comparison window (a patch included: it opens through the
    /// same `WindowGroup` and renders the same `ContentView` chrome, so it tabs alongside the rest rather than
    /// standing apart). The welcome window gets no identifier of its own -- see `WindowTabbingConfigurator`'s use
    /// in `App.swift` -- so it can never merge into this group.
    static let comparisonTabGroup = "comparison-group"
}

/// Bridges to the hosting `NSWindow` once AppKit attaches this view, to reach window-tab configuration
/// (`tabbingMode`, `tabbingIdentifier`) that has no SwiftUI-native surface on this SDK: `apple-docs` turned up
/// only the AppKit properties (confirmed against the macOS 26.5 SDK), no `Window`-scene modifier wrapping them.
/// Invisible and non-interactive by construction (see call sites' `.allowsHitTesting(false)`): it exists purely
/// to run `configure` once AppKit hands it a window, on `viewDidMoveToWindow`.
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

        // Never part of hit-testing: this view exists only to observe its window, not to draw or receive events.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

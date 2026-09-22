import AppKit
import AtelierGit
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
    /// window editing the app-wide base. Known limitation, documented on `adoptProject`: a base-default edit made
    /// in the Settings window afterward does not live-propagate into this instance's unoverridden keys.
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
            .onChange(of: model.currentConfiguration) { _, current in
                if let current { recents.record(current) }
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
                guard let root = await resolveProjectRoot() else { return }
                settings.adoptProject(ProjectIdentity(root: root))
            }
    }

    /// Where this window's project lives, resolved the same way `git` itself would: the repository root
    /// containing whichever path the launch configuration names, so a subfolder or a non-root path still maps to
    /// the same project as the rest of the repository. Patches carry no filesystem root of their own and stay
    /// unadopted -- their settings remain whatever the base currently holds.
    private func resolveProjectRoot() async -> URL? {
        let candidate: URL?
        switch configuration {
            case .patch: candidate = nil
            case .files(let left, _): candidate = left
            case .repository(let url, _, _): candidate = url
        }
        guard let candidate else { return nil }
        return await GitClient.repositoryRoot(containing: candidate, runner: services.runner)
    }
}

enum WindowID {
    static let welcome = "welcome"
    static let comparison = "comparison"
}

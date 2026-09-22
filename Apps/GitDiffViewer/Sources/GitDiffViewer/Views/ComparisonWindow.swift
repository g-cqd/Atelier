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
    let settings: ViewerSettings
    let recents: RecentComparisons
    let reader: any SourceReading
    let services: AppServices
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
        configuration: LaunchConfiguration, settings: ViewerSettings, recents: RecentComparisons,
        reader: any SourceReading, services: AppServices
    ) {
        self.configuration = configuration
        self.settings = settings
        self.recents = recents
        self.reader = reader
        self.services = services
        _model = State(initialValue: DiffViewerModel(settings: settings, reader: reader))
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
                model.start(configuration)
                recents.record(configuration)
                dismissWindow(id: WindowID.welcome)
            }
    }
}

enum WindowID {
    static let welcome = "welcome"
    static let comparison = "comparison"
}

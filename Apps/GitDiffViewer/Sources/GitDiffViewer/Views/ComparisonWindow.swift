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
    /// Created once the window appears: a state initialiser would run its git work on every re-creation of the view.
    @State private var model: DiffViewerModel?
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Group {
            if let model {
                ContentView(settings: settings, model: model)
                    .navigationTitle(model.windowTitle)
                    .onChange(of: model.currentConfiguration) { _, current in
                        if let current { recents.record(current) }
                    }
            } else {
                ProgressView()
            }
        }
        .onAppear {
            guard model == nil else { return }
            let model = DiffViewerModel(settings: settings)
            model.start(configuration)
            self.model = model
            recents.record(configuration)
            dismissWindow(id: WindowID.welcome)
        }
    }
}

enum WindowID {
    static let welcome = "welcome"
    static let comparison = "comparison"
}

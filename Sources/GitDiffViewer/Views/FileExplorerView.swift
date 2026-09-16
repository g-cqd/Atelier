import DiffComparison
import DiffCore
import DiffGit
import DiffRendering
import DiffTextKit
import Foundation
import SwiftUI

/// The file explorer of one comparison target; its source is chosen from the toolbar.
struct FileExplorerView: View {
    let side: SideState
    let model: DiffViewerModel
    let position: Side
    let isSidebar: Bool
    let uiState: ExplorerUIState

    var body: some View {
        FileOutlineView(
            sections: position == .left ? model.leftSections : model.rightSections,
            selectedPath: model.selectedPath.map { position == .left ? $0 : model.counterpartPath(of: $0, in: .left) },
            isSidebar: isSidebar,
            status: { model.status(of: $0, in: position) },
            onSelect: { model.select($0, from: position) },
            onPin: { model.pin($0, from: position) },
            uiState: uiState
        )
        .overlay {
            if side.source == nil {
                ContentUnavailableView(
                    "No source", systemImage: "folder.badge.questionmark",
                    description: Text("Pick a folder, repository or file above."))
            }
        }
    }
}

/// One merged tree for both sides, keyed by left-side paths.
struct UnifiedExplorerView: View {
    let model: DiffViewerModel
    let uiState: ExplorerUIState

    var body: some View {
        FileOutlineView(
            sections: model.unifiedSections,
            selectedPath: model.selectedPath,
            isSidebar: true,
            status: { model.status(ofPath: $0) },
            onSelect: { model.select($0, from: .left) },
            onPin: { model.pin($0, from: .left) },
            uiState: uiState
        )
        .overlay {
            if model.left.source == nil, model.right.source == nil {
                ContentUnavailableView(
                    "No sources", systemImage: "folder.badge.questionmark",
                    description: Text("Pick the two sides above."))
            }
        }
    }
}

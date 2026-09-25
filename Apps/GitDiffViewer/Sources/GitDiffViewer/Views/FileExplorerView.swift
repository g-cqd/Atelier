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
            uiState: uiState,
            badgeScheme: model.settings.badgeScheme,
            badgeStates: side.explorerBadgeStates
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
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            CommitGroupingStatusLine(state: model.commitGroups) { model.perform($0) }
            FileOutlineView(
                sections: model.unifiedSections,
                selectedPath: model.selectedPath,
                isSidebar: true,
                status: { model.status(ofPath: $0) },
                onSelect: { model.select($0, from: .left) },
                onPin: { model.pin($0, from: .left) },
                uiState: uiState,
                badgeScheme: model.settings.badgeScheme,
                badgeStates: model.unifiedBadgeStates,
                includesMergedBranches: model.commitGroups.includesMergedBranches,
                sectionMenu: { model.commitGroupMenu(forSelection: $0) },
                onOpenComparison: { openWindow(value: $0) }
            )
        }
        .overlay {
            if model.left.source == nil, model.right.source == nil {
                ContentUnavailableView(
                    "No sources", systemImage: "folder.badge.questionmark",
                    description: Text("Pick the two sides above."))
            }
        }
    }
}

/// The line above the merged sidebar's list while grouping by commit is on: why it does not apply, or that the
/// history is being read. Nothing while grouping is off, or on and settled (GIT-06).
struct CommitGroupingStatusLine: View {
    let state: CommitGroupsState
    /// Takes the way out the reason offers.
    let perform: (CommitGroupingAction) -> Void

    var body: some View {
        if let reason = state.eligibility?.ineligibility {
            line {
                Text(reason.message)
                if let action = reason.action {
                    Button(action.title) { perform(action) }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
        } else if state.isUpdating {
            line {
                ProgressView().controlSize(.mini)
                Text(state.grouping == nil ? "Reading the history…" : "Updating the history…")
            }
        }
    }

    private func line(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: 6) { content() }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
    }
}

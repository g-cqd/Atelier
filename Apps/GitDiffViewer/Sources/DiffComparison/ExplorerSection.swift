package import AtelierFileTree
import DiffCore
import DiffGit
import DiffRendering
package import Foundation
import Observation

/// One group of an explorer: the compared files, the files git ignores when they are shown as well, or, when the
/// merged sidebar's flat list is grouped by commit, one commit's files (GIT-06). With one section the explorer shows
/// its rows plainly; with several, each becomes a collapsible group.
package struct ExplorerSection: Equatable, Sendable, Identifiable {
    package enum Kind: Equatable, Sendable {
        case changes
        case ignored
        /// A section of the grouped list: Uncommitted Changes, a commit, or Earlier Changes.
        case commitGroup(CommitGrouping.Section)
    }

    package let kind: Kind
    package let title: String
    package let nodes: [PathNode]

    package init(kind: Kind, title: String, nodes: [PathNode]) {
        self.kind = kind
        self.title = title
        self.nodes = nodes
    }

    /// Stable across rebuilds; a commit group's is its ``CommitGrouping/Section/id``, which its fold is kept under.
    package var id: String {
        switch kind {
            case .changes: "changes"
            case .ignored: "ignored"
            case .commitGroup(let group): group.id
        }
    }

    /// The commit group this section shows; nil for the plain and ignored sections.
    package var commitGroup: CommitGrouping.Section? {
        if case .commitGroup(let group) = kind { group } else { nil }
    }

    /// A section of the grouped list, titled by its commit's subject, or by its fixed name.
    package init(group: CommitGrouping.Section) {
        let title =
            switch group.kind {
                case .uncommitted: "Uncommitted Changes"
                case .commit(let commit): commit.subject.isEmpty ? GitCommit.abbreviated(commit.id) : commit.subject
                case .earlier: "Earlier Changes"
            }
        // The rows come in the flat list's order already; sorting them again would cost as much as the grouping.
        let nodes = group.rows.map {
            PathNode(id: $0.path, name: ($0.path as NSString).lastPathComponent, isDirectory: false, children: nil)
        }
        self.init(kind: .commitGroup(group), title: title, nodes: nodes)
    }
}

/// How the grouped list presents its sections: which start folded, what their header says on hover, and the inert
/// lines a section shows (GIT-06).
extension ExplorerSection {
    /// Commit sections start unfolded up to this many commits, so a short range reads at once and a long one opens as
    /// a list of headers.
    package static let expandedCommitLimit = 20

    /// The ids of the sections that start folded: every commit section and Earlier Changes once the list holds more
    /// than ``expandedCommitLimit`` commits. Uncommitted Changes always starts unfolded.
    package static func collapsedByDefault(_ sections: [ExplorerSection]) -> Set<String> {
        let groups = sections.compactMap(\.commitGroup)
        let commits = groups.count { if case .commit = $0.kind { true } else { false } }
        guard commits > expandedCommitLimit else { return [] }
        return Set(groups.filter { $0.kind != .uncommitted }.map(\.id))
    }

    /// The inert lines under a section's files: why a section lists nothing, and how many older commits Earlier
    /// Changes stands for.
    package var noteLines: [String] {
        guard let group = commitGroup else { return [] }
        var lines = group.note.map { [$0] } ?? []
        if case .earlier(let unlisted?) = group.kind, unlisted > 0 {
            lines.append(unlisted == 1 ? "1 older commit not listed" : "\(unlisted) older commits not listed")
        }
        return lines
    }

    /// The header's tooltip, which the accessibility label reads too: for a commit, its short id, author and date,
    /// then its subject; then how many files were changed back, and whether the history includes merged branches.
    /// Nil for the plain and ignored sections.
    package func headerTooltip(includesMergedBranches: Bool, now: Date = .now) -> String? {
        guard let group = commitGroup else { return nil }
        var lines: [String]
        switch group.kind {
            case .uncommitted:
                lines = ["Changes in the working tree that no commit holds"]
            case .commit(let commit):
                let date = commit.authorDate.formatted(date: .abbreviated, time: .shortened)
                let formatter = RelativeDateTimeFormatter()
                formatter.dateTimeStyle = .named
                let relative = formatter.localizedString(for: commit.authorDate, relativeTo: now)
                lines = [
                    "\(GitCommit.abbreviated(commit.id)) · \(commit.authorName) · \(date) (\(relative))",
                    commit.subject
                ]
            case .earlier:
                lines = ["Changed files no listed commit touched"]
        }
        if group.changedBackCount > 0 {
            lines.append(
                group.changedBackCount == 1 ? "1 file changed back" : "\(group.changedBackCount) files changed back")
        }
        if includesMergedBranches, case .commit = group.kind { lines.append("History includes merged branches") }
        return lines.joined(separator: "\n")
    }

    /// Each file's path in this section's change, by row path, where it differs from the one shown.
    package var pathsInChange: [String: String] {
        guard let group = commitGroup else { return [:] }
        var paths: [String: String] = [:]
        for row in group.rows {
            if let path = row.pathInChange { paths[row.path] = path }
        }
        return paths
    }
}

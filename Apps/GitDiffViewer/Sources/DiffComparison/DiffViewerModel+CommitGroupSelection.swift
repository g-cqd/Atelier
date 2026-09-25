import DiffGit
import Foundation

/// A commit group chosen in the merged sidebar, as a selection: its files' net diff in a tab of its own, titled by
/// its commit (GIT-06, D31).
extension ExplorerSection {
    /// What starts the selection key of a section, and the id of its row in the outline. No path holds a NUL, so no
    /// file's key can collide with one.
    package static let selectionPrefix = "\u{0}section:"

    /// The key a section is selected, and shown in a tab, under.
    package static func selectionKey(forGroup id: String) -> String {
        selectionPrefix + id
    }

    /// The section id a selection key names, or nil for a file or folder path.
    package static func groupID(inSelection key: String) -> String? {
        key.hasPrefix(selectionPrefix) ? String(key.dropFirst(selectionPrefix.count)) : nil
    }
}

/// What a commit group's context menu offers.
package struct CommitGroupMenuItem: Equatable, Sendable {
    package enum Action: Equatable, Sendable {
        /// Opens a window comparing these two states.
        case compare(LaunchConfiguration)
        /// Puts this text on the pasteboard.
        case copy(String)
    }

    package let title: String
    /// Nil shows the item disabled.
    package let action: Action?
}

extension DiffViewerModel {
    /// The commit group a selection key names, when the grouping holds it.
    package func commitGroup(forSelection key: String) -> CommitGrouping.Section? {
        guard let id = ExplorerSection.groupID(inSelection: key) else { return nil }
        return commitGroups.grouping?.sections.first { $0.id == id }
    }

    /// The files a selected commit group opens, in the list's order, capped as the file list is; nil when `key` is a
    /// path. A group the grouping no longer holds opens nothing.
    func commitGroupPaths(forSelection key: String, limit: Int) -> [String]? {
        guard ExplorerSection.groupID(inSelection: key) != nil else { return nil }
        return commitGroup(forSelection: key).map { Array($0.rows.map(\.path).prefix(limit)) } ?? []
    }

    /// How a tab or the status bar names a selection: a commit group by its title, a file or folder by its name.
    package func selectionTitle(_ key: String) -> String {
        if let group = commitGroup(forSelection: key) { return ExplorerSection(group: group).title }
        if ExplorerSection.groupID(inSelection: key) != nil { return "Commit" }
        return URL(filePath: key).lastPathComponent
    }

    /// How the status bar names a selection: a commit group by its title, a file or folder by its path.
    package func selectionLabel(_ key: String) -> String {
        ExplorerSection.groupID(inSelection: key) == nil ? key : selectionTitle(key)
    }

    /// A selection's longer description, for a tab's tooltip: a commit group's header tooltip, else the path.
    package func selectionDetail(_ key: String) -> String {
        guard let group = commitGroup(forSelection: key) else { return key }
        return ExplorerSection(group: group).headerTooltip(includesMergedBranches: commitGroups.includesMergedBranches)
            ?? key
    }

    /// Whether `key` still names something to show: a file or folder of the comparison, or a commit group; a group
    /// counts while the grouping is loading, since its sections come back once it lands.
    func selectionExists(_ key: String) -> Bool {
        guard ExplorerSection.groupID(inSelection: key) != nil else { return comparison.contains(key) }
        return commitGroups.isUpdating || commitGroup(forSelection: key) != nil
    }

    /// Closes the tabs of commit groups the settled grouping no longer holds, and moves the selection off one.
    func dropVanishedCommitGroupTabs() {
        tabs.keepOnly(where: selectionExists)
        if let selectedPath, !selectionExists(selectedPath) {
            applySelection(tabs.activePath, keepingPublished: true)
        }
    }

    /// What a commit group's context menu offers: for a commit, comparing its first parent with it and copying its
    /// id; for Earlier Changes, comparing the left side with the oldest listed commit's first parent, the range it
    /// stands for. Empty for Uncommitted Changes and for a key that names no group.
    package func commitGroupMenu(forSelection key: String) -> [CommitGroupMenuItem] {
        guard let group = commitGroup(forSelection: key), case .applies(let range) = commitGroups.eligibility else {
            return []
        }
        switch group.kind {
            case .commit(let commit):
                let parent = commit.parentIDs.first
                return [
                    CommitGroupMenuItem(
                        title: "Compare This Commit",
                        action: parent.map { .compare(.repository(range.repository, leftRef: $0, rightRef: commit.id)) }
                    ),
                    CommitGroupMenuItem(title: "Copy Commit ID", action: .copy(commit.id))
                ]
            case .earlier:
                let oldestListed = commitGroups.grouping?.sections
                    .last { if case .commit = $0.kind { true } else { false } }
                guard case .commit(let oldest)? = oldestListed?.kind, let parent = oldest.parentIDs.first else {
                    return [CommitGroupMenuItem(title: "Compare This Range", action: nil)]
                }
                return [
                    CommitGroupMenuItem(
                        title: "Compare This Range",
                        action: .compare(.repository(range.repository, leftRef: range.base, rightRef: parent)))
                ]
            case .uncommitted:
                return []
        }
    }
}

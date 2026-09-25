import DiffGit
import Foundation

/// A commit group chosen in the merged sidebar, or one file under it, as a selection: the group's own change in a tab
/// of its own, titled by its commit (GIT-06, D39).
extension ExplorerSection {
    /// What starts the selection key of a section, and the id of its row in the outline. No path holds a NUL, so no
    /// file's key can collide with one.
    package static let selectionPrefix = "\u{0}section:"
    /// What parts a section's id from the path of a file under it, in that file's selection key.
    private static let pathSeparator: Character = "\u{0}"

    /// The key a section is selected, and shown in a tab, under.
    package static func selectionKey(forGroup id: String) -> String {
        selectionPrefix + id
    }

    /// The key a file under a section is selected under: the section and the path, so the same file under two
    /// commits is two selections, two tabs and two rows.
    package static func selectionKey(forGroup id: String, path: String) -> String {
        selectionPrefix + id + String(pathSeparator) + path
    }

    /// The section id a selection key names, a section's or a file's under it; nil for a plain file or folder path.
    package static func groupID(inSelection key: String) -> String? {
        guard key.hasPrefix(selectionPrefix) else { return nil }
        return String(key.dropFirst(selectionPrefix.count).prefix { $0 != pathSeparator })
    }

    /// The path of the file a selection key names under a section; nil for a section's own key and a plain path.
    package static func path(inSelection key: String) -> String? {
        guard key.hasPrefix(selectionPrefix) else { return nil }
        let rest = key.dropFirst(selectionPrefix.count)
        return rest.firstIndex(of: pathSeparator).map { String(rest[rest.index(after: $0)...]) }
    }

    /// Whether `key` names a section itself, not a file under it nor a plain path.
    package static func isSectionSelection(_ key: String) -> Bool {
        key.hasPrefix(selectionPrefix) && path(inSelection: key) == nil
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
    /// The commit group a selection key names, the section's or a file's under it, when the grouping holds it.
    package func commitGroup(forSelection key: String) -> CommitGrouping.Section? {
        guard let id = ExplorerSection.groupID(inSelection: key) else { return nil }
        return commitGroups.grouping?.sections.first { $0.id == id }
    }

    /// The files a selected commit group opens, in the list's order, capped as the file list is; nil when `key` is a
    /// path. A group the grouping no longer holds opens nothing.
    func commitGroupPaths(forSelection key: String, limit: Int) -> [String]? {
        guard ExplorerSection.isSectionSelection(key) else { return nil }
        return commitGroup(forSelection: key).map { Array($0.rows.map(\.path).prefix(limit)) } ?? []
    }

    /// How a tab names a selection: a commit group by its subject and short id, a file under one by its name and the
    /// group's, a plain file or folder by its name.
    package func selectionTitle(_ key: String) -> String {
        guard ExplorerSection.groupID(inSelection: key) != nil else {
            return URL(filePath: key).lastPathComponent
        }
        let context = commitGroup(forSelection: key).map(Self.context(of:)) ?? "Commit"
        guard let path = ExplorerSection.path(inSelection: key) else { return context }
        return "\(URL(filePath: path).lastPathComponent) · \(context)"
    }

    /// How the status bar says where what it shows comes from: a commit group, the section a file is shown under, or
    /// a plain file or folder by its path.
    package func selectionLabel(_ key: String) -> String {
        guard ExplorerSection.groupID(inSelection: key) != nil else { return key }
        return commitGroup(forSelection: key).map(Self.context(of:)) ?? "Commit"
    }

    /// A selection's longer description, for a tab's tooltip: a commit group's header tooltip, after the file's path
    /// for a file under one, else the path.
    package func selectionDetail(_ key: String) -> String {
        let path = ExplorerSection.path(inSelection: key)
        guard let group = commitGroup(forSelection: key) else { return path ?? key }
        let header =
            ExplorerSection(group: group).headerTooltip(includesMergedBranches: commitGroups.includesMergedBranches)
            ?? ""
        guard let path else { return header.isEmpty ? key : header }
        return header.isEmpty ? path : path + "\n" + header
    }

    /// A group as the tab and the status bar name it: a commit by its subject and short id, a fixed section by its
    /// title.
    private static func context(of group: CommitGrouping.Section) -> String {
        let title = ExplorerSection(group: group).title
        guard case .commit(let commit) = group.kind, !commit.subject.isEmpty else { return title }
        return "\(title) · \(GitCommit.abbreviated(commit.id))"
    }

    /// Whether `key` still names something to show: a file or folder of the comparison, or a commit group; a group
    /// counts while the grouping is loading, since its sections come back once it lands.
    func selectionExists(_ key: String) -> Bool {
        guard ExplorerSection.groupID(inSelection: key) != nil else { return comparison.contains(key) }
        if commitGroups.isUpdating { return true }
        guard let group = commitGroup(forSelection: key) else { return false }
        guard let path = ExplorerSection.path(inSelection: key) else { return true }
        return group.rows.contains { $0.path == path }
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
    /// stands for. Empty for Uncommitted Changes, for a file under a group and for a key that names no group.
    package func commitGroupMenu(forSelection key: String) -> [CommitGroupMenuItem] {
        guard ExplorerSection.isSectionSelection(key), let group = commitGroup(forSelection: key),
            case .applies(let range) = commitGroups.eligibility
        else {
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

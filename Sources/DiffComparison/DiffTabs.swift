package import Foundation

/// A tab over a file or a folder of the comparison.
package struct DiffTab: Identifiable, Equatable, Sendable {
    package let id: UUID
    /// Left-side path of the file or folder shown.
    package var path: String
    /// A temporary tab is replaced by the next single click; a pinned one stays until closed.
    package var isPinned: Bool

    package init(id: UUID = UUID(), path: String, isPinned: Bool) {
        self.id = id
        self.path = path
        self.isPinned = isPinned
    }
}

/// Editor-style tabs: a single click opens a temporary tab, or reuses the existing temporary one; a double click
/// pins. With no tab open, the whole list of changed files shows.
package struct DiffTabs: Equatable, Sendable {
    package private(set) var tabs: [DiffTab] = []
    package private(set) var activeID: DiffTab.ID?

    package init() {}

    package var active: DiffTab? { tabs.first { $0.id == activeID } }
    package var activePath: String? { active?.path }

    /// Shows `path` in the temporary tab, creating it after the active tab when there is none.
    package mutating func open(_ path: String) {
        if let index = tabs.firstIndex(where: { $0.path == path }) {
            activeID = tabs[index].id
            return
        }
        if let index = tabs.firstIndex(where: { !$0.isPinned }) {
            tabs[index].path = path
            activeID = tabs[index].id
            return
        }
        insert(DiffTab(path: path, isPinned: false))
    }

    /// Shows `path` in a pinned tab: the tab already showing it becomes pinned, else a new pinned tab opens.
    package mutating func pin(_ path: String) {
        if let index = tabs.firstIndex(where: { $0.path == path }) {
            tabs[index].isPinned = true
            activeID = tabs[index].id
            return
        }
        insert(DiffTab(path: path, isPinned: true))
    }

    package mutating func pin(_ id: DiffTab.ID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].isPinned = true
        activeID = id
    }

    package mutating func activate(_ id: DiffTab.ID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeID = id
    }

    /// Closes a tab; the neighbour takes over, or nothing when it was the last one.
    package mutating func close(_ id: DiffTab.ID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)
        if activeID == id {
            activeID = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)].id
        }
    }

    package mutating func closeAll() {
        tabs = []
        activeID = nil
    }

    /// Drops tabs whose path no longer exists in the comparison.
    package mutating func keepOnly(where isValid: (String) -> Bool) {
        for tab in tabs where !isValid(tab.path) { close(tab.id) }
    }

    private mutating func insert(_ tab: DiffTab) {
        let position = active.flatMap { active in tabs.firstIndex { $0.id == active.id } }.map { $0 + 1 } ?? tabs.count
        tabs.insert(tab, at: position)
        activeID = tab.id
    }
}

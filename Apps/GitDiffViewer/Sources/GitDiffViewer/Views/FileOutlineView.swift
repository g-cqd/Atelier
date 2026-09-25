import AppKit
import AtelierFileTree
import DiffComparison
import DiffCore
import DiffGit
import DiffRendering
import DiffTextKit
import Foundation
import SwiftUI

/// A file tree as a native outline view: arrow keys, type-select, native selection and disclosure, and a cost
/// bounded by the visible rows. SwiftUI's outline list re-walks every item on each change, which costs seconds on
/// a large tree; a SwiftUI flat list is quick but has no keyboard navigation and no native selection.
///
/// Inputs are values, so an update compares them and touches the view only for what changed: new `sections`
/// rebuild the items, anything else reconfigures the visible cells in place. One section shows its rows plainly;
/// several become collapsible group rows, the way a source list sections its content.
struct FileOutlineView: NSViewRepresentable {
    let sections: [ExplorerSection]
    /// The path to show selected, in this explorer's own paths.
    let selectedPath: String?
    /// Sidebar placements take the source-list look, whose row height and font follow the system sidebar size.
    let isSidebar: Bool
    let status: (String) -> PathStatus?
    let onSelect: (String) -> Void
    let onPin: (String) -> Void
    let uiState: ExplorerUIState
    /// Which colours a badge's letter is drawn in.
    var badgeScheme: BadgeScheme = .classic
    /// Where each row's change stands against the index, keyed by this explorer's own paths.
    var badgeStates: BadgeChangeStates = .uniform(.staged)
    /// Whether the grouped list's history was read with every parent, which its commit headers say on hover.
    var includesMergedBranches = false

    func makeCoordinator() -> Coordinator {
        Coordinator(uiState: uiState)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let coordinator = context.coordinator
        let outline = KeyboardOutlineView()
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("file"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.headerView = nil
        outline.usesAutomaticRowHeights = false
        outline.allowsTypeSelect = true
        outline.allowsMultipleSelection = false
        outline.allowsColumnReordering = false
        outline.allowsColumnResizing = false
        // Off: on, every expansion widens the column past the pane and pushes the trailing badges out of sight.
        outline.autoresizesOutlineColumn = false
        outline.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        outline.focusRingType = .none
        outline.backgroundColor = .clear
        outline.dataSource = coordinator
        outline.delegate = coordinator
        outline.target = coordinator
        outline.doubleAction = #selector(Coordinator.doubleClicked(_:))
        outline.onReturn = { [weak coordinator] in coordinator?.pinSelection() }
        outline.onSpace = { [weak coordinator] in coordinator?.toggleSelectedDisclosure() ?? false }
        coordinator.outlineView = outline
        coordinator.applyPlacement(isSidebar: isSidebar, to: outline)

        let scrollView = NSScrollView()
        scrollView.documentView = outline
        // Follows the width of the clip view, so the single column always fills the pane.
        outline.autoresizingMask = [.width]
        outline.frame = scrollView.contentView.bounds
        // Rows scroll under the toolbar and are blurred by it, instead of stopping at a hard edge below it.
        scrollView.automaticallyAdjustsContentInsets = true
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        guard let outline = coordinator.outlineView else { return }
        coordinator.status = status
        coordinator.onSelect = onSelect
        coordinator.onPin = onPin
        coordinator.uiState = uiState
        coordinator.badgeScheme = badgeScheme
        coordinator.badgeStates = badgeStates
        coordinator.includesMergedBranches = includesMergedBranches
        if coordinator.isSidebar != isSidebar {
            coordinator.applyPlacement(isSidebar: isSidebar, to: outline)
        }
        if coordinator.sections != sections {
            coordinator.sections = sections
            coordinator.rebuild(in: outline, selecting: selectedPath)
        } else {
            coordinator.reconfigureVisibleRows(in: outline)
        }
        coordinator.apply(selection: selectedPath, in: outline)
    }

    /// Data source and delegate. Items are reused across rebuilds through `itemsByKey`, so the outline view's own
    /// expansion and selection bookkeeping keeps matching them. A file listed under several commit sections has a row,
    /// and a key, in each; a selection of its path lands on the row last clicked, else on the newest section's.
    /// Main-actor by the target's default isolation.
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        /// Section rows take ids no path can have, so they never collide with a file in `itemsByKey`.
        private static let sectionPrefix = "\u{0}section:"

        var sections: [ExplorerSection] = []
        var isSidebar = false
        var status: (String) -> PathStatus? = { _ in nil }
        var onSelect: (String) -> Void = { _ in }
        var onPin: (String) -> Void = { _ in }
        var uiState: ExplorerUIState
        var badgeScheme: BadgeScheme = .classic
        var badgeStates: BadgeChangeStates = .uniform(.staged)
        var includesMergedBranches = false
        weak var outlineView: NSOutlineView?

        private var roots: [OutlineItem] = []
        private var itemsByKey: [String: OutlineItem] = [:]
        /// Every row of a path, in outline order: one, or one per commit section that lists it.
        private var itemsByPath: [String: [OutlineItem]] = [:]
        /// The sections that start folded when the user never folded or unfolded them.
        private var collapsedByDefault: Set<String> = []
        /// The selection last put in the view, by the model or by the user; a model selection equal to it is a no-op.
        private var lastAppliedSelection: String?
        private var isApplyingModelSelection = false
        private var isRestoringExpansion = false
        /// AppKit moves the selection onto a folder it collapses over the selected row; that is a side effect of
        /// the disclosure, not a choice, and selecting a folder renders every changed file under it.
        private var isCollapsing = false

        init(uiState: ExplorerUIState) {
            self.uiState = uiState
        }

        func applyPlacement(isSidebar: Bool, to outline: NSOutlineView) {
            self.isSidebar = isSidebar
            outline.style = isSidebar ? .sourceList : .inset
            outline.rowSizeStyle = isSidebar ? .default : .small
        }

        // MARK: Items

        /// Rebuilds the items for `sections`, reusing instances by path, and restores the expansion and the selection.
        /// - Complexity: O(nodes)
        func rebuild(in outline: NSOutlineView, selecting path: String?) {
            let started = ContinuousClock.now
            defer {
                PhaseTrace.log(
                    "explorer rebuilt: \(itemsByKey.count) items, \(outline.numberOfRows) rows in \((ContinuousClock.now - started).formatted(.units(allowed: [.milliseconds], fractionalPart: .show(length: 1))))"
                )
            }
            var reused: [String: OutlineItem] = [:]
            var byPath: [String: [OutlineItem]] = [:]
            /// `scope` keys the rows of a commit section apart from the same paths under another one.
            func build(_ node: PathNode, parent: OutlineItem?, continuesChain: Bool, scope: String? = nil)
                -> OutlineItem
            {
                let key = scope.map { $0 + "\u{0}" + node.id } ?? node.id
                let item = itemsByKey[key] ?? OutlineItem(key: key, node: node)
                item.node = node
                item.parent = parent
                byPath[node.id, default: []].append(item)
                // The head of a chain is keyed by the whole chain, so a fold survives a switch to the compact style,
                // where the chain is one row. The links below it have no row there, so they take a key of their own;
                // the bare id would not do, since the deepest link's id is the head's chain key.
                item.chainKey = continuesChain ? "\u{1}" + node.id : node.chainKey
                let childContinues = node.children?.count == 1 && node.children?.first?.isDirectory == true
                item.children = (node.children ?? []).map { build($0, parent: item, continuesChain: childContinues) }
                reused[key] = item
                return item
            }
            if sections.count == 1, let only = sections.first, only.commitGroup == nil {
                roots = only.nodes.map { build($0, parent: nil, continuesChain: false) }
            } else {
                roots = sections.map { section in
                    let node = PathNode(
                        id: Self.sectionPrefix + section.id, name: section.title, isDirectory: true,
                        children: section.nodes)
                    let item = itemsByKey[node.id] ?? OutlineItem(key: node.id, node: node)
                    item.node = node
                    item.parent = nil
                    item.chainKey = node.id
                    item.isSection = true
                    item.section = section
                    let scope = section.commitGroup.map { _ in section.id }
                    let details = section.pathsInChange
                    let files = section.nodes.map { child in
                        let row = build(child, parent: item, continuesChain: false, scope: scope)
                        row.detail = details[child.id].map { "Named \($0) in this commit" }
                        return row
                    }
                    item.children = files + noteItems(of: section, under: item, keyedBy: node.id, into: &reused)
                    reused[node.id] = item
                    return item
                }
            }
            collapsedByDefault = Set(ExplorerSection.collapsedByDefault(sections).map { Self.sectionPrefix + $0 })
            itemsByKey = reused
            itemsByPath = byPath
            reload(in: outline, selecting: path)
        }

        /// Reloads every row (trees change wholesale, so no animated insertions), then applies the expansion state
        /// and re-selects the model's path if it is visible.
        func reload(in outline: NSOutlineView, selecting path: String?) {
            isApplyingModelSelection = true
            isRestoringExpansion = true
            outline.reloadData()
            outline.beginUpdates()
            applyExpansionState(to: roots, in: outline)
            outline.endUpdates()
            isRestoringExpansion = false
            restoreSelection(path, in: outline, revealing: false)
            isApplyingModelSelection = false
        }

        /// Folders are expanded unless their chain is folded; parents first, and only under expanded parents, since
        /// a hidden folder cannot be expanded and gets its state when its parent opens.
        private func applyExpansionState(to items: [OutlineItem], in outline: NSOutlineView) {
            for item in items where item.node.isDirectory {
                if uiState.isCollapsed(item.chainKey, byDefault: collapsedByDefault.contains(item.chainKey)) {
                    if outline.isItemExpanded(item) { outline.collapseItem(item) }
                } else {
                    if !outline.isItemExpanded(item) { outline.expandItem(item) }
                    applyExpansionState(to: item.children, in: outline)
                }
            }
        }

        /// Statuses changed: the visible cells take the new values, nothing is reloaded or scrolled.
        func reconfigureVisibleRows(in outline: NSOutlineView) {
            outline.enumerateAvailableRowViews { rowView, row in
                guard let item = outline.item(atRow: row) as? OutlineItem,
                    let cell = rowView.view(atColumn: 0) as? FileCellView
                else { return }
                self.configure(cell, for: item)
            }
        }

        // MARK: Selection

        /// The model's selection changed (a tab activated, a file auto-selected, the other explorer clicked): reveal it.
        func apply(selection path: String?, in outline: NSOutlineView) {
            guard path != lastAppliedSelection else { return }
            lastAppliedSelection = path
            isApplyingModelSelection = true
            defer { isApplyingModelSelection = false }
            guard let path, let item = row(for: path, in: outline) else {
                outline.deselectAll(nil)
                return
            }
            var ancestors: [OutlineItem] = []
            var parent = item.parent
            while let ancestor = parent {
                ancestors.append(ancestor)
                parent = ancestor.parent
            }
            for ancestor in ancestors.reversed() where !outline.isItemExpanded(ancestor) {
                outline.expandItem(ancestor)
            }
            restoreSelection(path, in: outline, revealing: true)
        }

        /// Selects `path` when it has a row, without opening the folders above it. Only a selection the model just
        /// moved is worth scrolling to; a rebuild keeps the user where they were.
        private func restoreSelection(_ path: String?, in outline: NSOutlineView, revealing: Bool) {
            guard let path, let item = row(for: path, in: outline) else {
                if outline.selectedRow >= 0 { outline.deselectAll(nil) }
                return
            }
            let row = outline.row(forItem: item)
            guard row >= 0 else { return }
            if outline.selectedRow != row {
                outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
            if revealing { outline.scrollRowToVisible(row) }
        }

        private func selectedItem(in outline: NSOutlineView) -> OutlineItem? {
            outline.selectedRow >= 0 ? outline.item(atRow: outline.selectedRow) as? OutlineItem : nil
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !isApplyingModelSelection, !isCollapsing, let outline = outlineView else { return }
            guard let item = selectedItem(in: outline) else {
                // Losing the selection would close every tab; too easy to hit by accident, so it is put back.
                isApplyingModelSelection = true
                restoreSelection(lastAppliedSelection, in: outline, revealing: false)
                isApplyingModelSelection = false
                return
            }
            guard item.path != lastAppliedSelection else { return }
            lastAppliedSelection = item.path
            onSelect(item.path)
        }

        @objc func doubleClicked(_ sender: NSOutlineView) {
            let row = sender.clickedRow
            guard row >= 0, let item = sender.item(atRow: row) as? OutlineItem else { return }
            // A double action replaces the native toggle on folders; return pins them.
            if item.node.isDirectory {
                if sender.isItemExpanded(item) { sender.collapseItem(item) } else { sender.expandItem(item) }
            } else if !item.isNote {
                onPin(item.path)
            }
        }

        func pinSelection() {
            guard let outline = outlineView, let item = selectedItem(in: outline) else { return }
            lastAppliedSelection = item.path
            onPin(item.path)
        }

        /// Whether a folder was selected to toggle; otherwise the key goes to type-select.
        func toggleSelectedDisclosure() -> Bool {
            guard let outline = outlineView, let item = selectedItem(in: outline), item.node.isDirectory else {
                return false
            }
            if outline.isItemExpanded(item) { outline.collapseItem(item) } else { outline.expandItem(item) }
            return true
        }

        // MARK: Expansion

        func outlineViewItemDidExpand(_ notification: Notification) {
            guard let item = notification.userInfo?["NSObject"] as? OutlineItem, let outline = outlineView else {
                return
            }
            // A section's default fold is not the user's choice, so only a fold the user made is remembered for it.
            if !item.isSection || !isRestoringExpansion { uiState.setCollapsed(false, item.chainKey) }
            guard !isRestoringExpansion else { return }
            // Folders that appeared while this one was folded come up in their remembered state.
            isRestoringExpansion = true
            applyExpansionState(to: item.children, in: outline)
            isRestoringExpansion = false
            // A collapse moved the highlight onto this folder; its file is the selection again now that it shows.
            isApplyingModelSelection = true
            restoreSelection(lastAppliedSelection, in: outline, revealing: false)
            isApplyingModelSelection = false
        }

        func outlineViewItemWillCollapse(_ notification: Notification) {
            isCollapsing = true
        }

        func outlineViewItemDidCollapse(_ notification: Notification) {
            isCollapsing = false
            guard let item = notification.userInfo?["NSObject"] as? OutlineItem else { return }
            if !item.isSection || !isRestoringExpansion { uiState.setCollapsed(true, item.chainKey) }
        }

        // MARK: Data source

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            ((item as? OutlineItem)?.children ?? roots).count
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            ((item as? OutlineItem)?.children ?? roots)[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            (item as? OutlineItem)?.node.isDirectory == true
        }

        func outlineView(_ outlineView: NSOutlineView, objectValueFor tableColumn: NSTableColumn?, byItem item: Any?)
            -> Any?
        {
            item
        }
    }
}

/// The outline's rows as views, and which of them select.
extension FileOutlineView.Coordinator {
    // MARK: Rows

    /// The inert lines under a section's files, reused by key like every other row.
    private func noteItems(
        of section: ExplorerSection, under parent: OutlineItem, keyedBy sectionKey: String,
        into reused: inout [String: OutlineItem]
    ) -> [OutlineItem] {
        section.noteLines.enumerated()
            .map { index, text in
                let key = sectionKey + "\u{0}note\(index)"
                let node = PathNode(id: key, name: text, isDirectory: false, children: nil)
                let note = itemsByKey[key] ?? OutlineItem(key: key, node: node)
                note.node = node
                note.parent = parent
                note.isNote = true
                reused[key] = note
                return note
            }
    }

    /// The row that shows `path`: the selected one when it already does, as after a click on one of a file's
    /// rows, else the first in outline order, which is the newest commit section's.
    private func row(for path: String, in outline: NSOutlineView) -> OutlineItem? {
        if let selected = selectedItem(in: outline), selected.path == path { return selected }
        return itemsByPath[path]?.first
    }

    // MARK: Delegate

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let item = item as? OutlineItem else { return nil }
        if item.isSection, let section = item.section, let group = section.commitGroup {
            let header =
                outlineView.makeView(withIdentifier: CommitSectionCellView.identifier, owner: nil)
                as? CommitSectionCellView ?? CommitSectionCellView()
            header.configure(
                title: section.title, count: group.rows.count,
                tooltip: section.headerTooltip(includesMergedBranches: includesMergedBranches))
            return header
        }
        if item.isSection {
            let header =
                outlineView.makeView(withIdentifier: SectionCellView.identifier, owner: nil) as? SectionCellView
                ?? SectionCellView()
            header.textField?.stringValue = item.node.name
            return header
        }
        if item.isNote {
            let note =
                outlineView.makeView(withIdentifier: NoteCellView.identifier, owner: nil) as? NoteCellView
                ?? NoteCellView()
            note.textField?.stringValue = item.node.name
            return note
        }
        let cell =
            outlineView.makeView(withIdentifier: FileCellView.identifier, owner: nil) as? FileCellView
            ?? FileCellView()
        configure(cell, for: item)
        return cell
    }

    /// A plain section heads its rows as a source list's group row; a commit section is an ordinary row drawn as a
    /// header, since a group row can never be selected.
    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        guard let item = item as? OutlineItem else { return false }
        return item.isSection && item.section?.commitGroup == nil
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        guard let item = item as? OutlineItem else { return false }
        return !item.isSection && !item.isNote
    }

    func outlineView(_ outlineView: NSOutlineView, typeSelectStringFor tableColumn: NSTableColumn?, item: Any)
        -> String?
    {
        guard let item = item as? OutlineItem, !item.isSection, !item.isNote else { return nil }
        return item.node.name
    }

    private func configure(_ cell: FileCellView, for item: OutlineItem) {
        cell.configure(
            node: item.node, glyph: status(item.path).flatMap(ChangeGlyph.init), scheme: badgeScheme,
            state: badgeStates.state(of: item.path), detail: item.detail)
    }
}

/// One row of the outline, kept between rebuilds so the outline view recognises it.
final class OutlineItem: NSObject {
    /// Unique in the outline: the path, scoped by its commit section when the list is grouped by commit.
    let key: String
    var node: PathNode
    var children: [OutlineItem] = []
    /// See ``PathNode/chainKey``.
    var chainKey: String
    /// A row heading one of the explorer's sections; it has no file.
    var isSection = false
    /// The section a header row heads.
    var section: ExplorerSection?
    /// An inert line inside a section, such as "No net changes": no file, never selected.
    var isNote = false
    /// What a file row's tooltip adds, such as the name it had in its commit.
    var detail: String?
    weak var parent: OutlineItem?

    /// The model's path for the row: the file or folder it shows.
    var path: String { node.id }

    init(key: String, node: PathNode) {
        self.key = key
        self.node = node
        chainKey = node.id
    }
}

/// Return pins the selection and space toggles the selected folder; clicks on empty space keep the selection.
final class KeyboardOutlineView: NSOutlineView {
    var onReturn: (() -> Void)?
    /// Returns whether the key was used; a space over a file belongs to type-select.
    var onSpace: (() -> Bool)?

    override func keyDown(with event: NSEvent) {
        switch event.charactersIgnoringModifiers {
            case "\r", "\u{3}":
                onReturn?()
            case " " where onSpace?() == true:
                return
            default:
                super.keyDown(with: event)
        }
    }

    /// A click in an inactive window selects, as the SwiftUI rows did.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        guard row(at: convert(event.locationInWindow, from: nil)) >= 0 else {
            window?.makeFirstResponder(self)
            return
        }
        super.mouseDown(with: event)
    }
}

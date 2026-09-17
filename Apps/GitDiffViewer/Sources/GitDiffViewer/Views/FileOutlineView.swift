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
    /// expansion and selection bookkeeping keeps matching them. Main-actor by the target's default isolation.
    final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        /// Section rows take ids no path can have, so they never collide with a file in `itemsByKey`.
        private static let sectionPrefix = "\u{0}section:"

        var sections: [ExplorerSection] = []
        var isSidebar = false
        var status: (String) -> PathStatus? = { _ in nil }
        var onSelect: (String) -> Void = { _ in }
        var onPin: (String) -> Void = { _ in }
        var uiState: ExplorerUIState
        weak var outlineView: NSOutlineView?

        private var roots: [OutlineItem] = []
        private var itemsByKey: [String: OutlineItem] = [:]
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
            func build(_ node: PathNode, parent: OutlineItem?, continuesChain: Bool) -> OutlineItem {
                let item = itemsByKey[node.id] ?? OutlineItem(node: node)
                item.node = node
                item.parent = parent
                // The head of a chain is keyed by the whole chain, so a fold survives a switch to the compact style,
                // where the chain is one row. The links below it have no row there, so they take a key of their own;
                // the bare id would not do, since the deepest link's id is the head's chain key.
                item.chainKey = continuesChain ? "\u{1}" + node.id : node.chainKey
                let childContinues = node.children?.count == 1 && node.children?.first?.isDirectory == true
                item.children = (node.children ?? []).map { build($0, parent: item, continuesChain: childContinues) }
                reused[node.id] = item
                return item
            }
            if sections.count == 1, let only = sections.first {
                roots = only.nodes.map { build($0, parent: nil, continuesChain: false) }
            } else {
                roots = sections.map { section in
                    let node = PathNode(
                        id: Self.sectionPrefix + section.id, name: section.title, isDirectory: true,
                        children: section.nodes)
                    let item = itemsByKey[node.id] ?? OutlineItem(node: node)
                    item.node = node
                    item.parent = nil
                    item.chainKey = node.id
                    item.isSection = true
                    item.children = section.nodes.map { build($0, parent: item, continuesChain: false) }
                    reused[node.id] = item
                    return item
                }
            }
            itemsByKey = reused
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
                if uiState.isCollapsed(item.chainKey) {
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
            guard let path, let item = itemsByKey[path] else {
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
            guard let path, let item = itemsByKey[path] else {
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
            guard item.key != lastAppliedSelection else { return }
            lastAppliedSelection = item.key
            onSelect(item.key)
        }

        @objc func doubleClicked(_ sender: NSOutlineView) {
            let row = sender.clickedRow
            guard row >= 0, let item = sender.item(atRow: row) as? OutlineItem else { return }
            // A double action replaces the native toggle on folders; return pins them.
            if item.node.isDirectory {
                if sender.isItemExpanded(item) { sender.collapseItem(item) } else { sender.expandItem(item) }
            } else {
                onPin(item.key)
            }
        }

        func pinSelection() {
            guard let outline = outlineView, let item = selectedItem(in: outline) else { return }
            lastAppliedSelection = item.key
            onPin(item.key)
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
            uiState.setCollapsed(false, item.chainKey)
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
            uiState.setCollapsed(true, item.chainKey)
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

        // MARK: Delegate

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let item = item as? OutlineItem else { return nil }
            if item.isSection {
                let header =
                    outlineView.makeView(withIdentifier: SectionCellView.identifier, owner: nil) as? SectionCellView
                    ?? SectionCellView()
                header.textField?.stringValue = item.node.name
                return header
            }
            let cell =
                outlineView.makeView(withIdentifier: FileCellView.identifier, owner: nil) as? FileCellView
                ?? FileCellView()
            configure(cell, for: item)
            return cell
        }

        func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
            (item as? OutlineItem)?.isSection == true
        }

        func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
            (item as? OutlineItem)?.isSection == false
        }

        func outlineView(_ outlineView: NSOutlineView, typeSelectStringFor tableColumn: NSTableColumn?, item: Any)
            -> String?
        {
            guard let item = item as? OutlineItem, !item.isSection else { return nil }
            return item.node.name
        }

        private func configure(_ cell: FileCellView, for item: OutlineItem) {
            cell.configure(node: item.node, glyph: status(item.key).flatMap(ChangeGlyph.init))
        }
    }
}

/// One row of the outline, kept between rebuilds so the outline view recognises it.
final class OutlineItem: NSObject {
    let key: String
    var node: PathNode
    var children: [OutlineItem] = []
    /// See ``PathNode/chainKey``.
    var chainKey: String
    /// A group row heading one of the explorer's sections; it has no file and cannot be selected.
    var isSection = false
    weak var parent: OutlineItem?

    init(node: PathNode) {
        key = node.id
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

/// The heading of a section; the outline view gives group rows their look, this only provides the text field.
final class SectionCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("SectionCellView")

    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = Self.identifier
        let text = NSTextField(labelWithString: "")
        text.lineBreakMode = .byTruncatingTail
        text.translatesAutoresizingMaskIntoConstraints = false
        addSubview(text)
        textField = text
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            text.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            text.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

/// Icon, name and the change badge at the trailing edge, the same badge as the file cards. The standard outlets
/// let the source-list style size the font and the icon after the system sidebar setting.
final class FileCellView: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("FileCellView")

    private let badge = ChangeBadgeView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = Self.identifier
        let image = NSImageView()
        image.imageScaling = .scaleProportionallyDown
        image.setContentHuggingPriority(.required, for: .horizontal)
        image.setContentCompressionResistancePriority(.required, for: .horizontal)
        let text = NSTextField(labelWithString: "")
        text.lineBreakMode = .byTruncatingTail
        text.cell?.truncatesLastVisibleLine = true
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for view in [image, text, badge] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        imageView = image
        textField = text
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            image.centerYAnchor.constraint(equalTo: centerYAnchor),
            text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 5),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
            text.trailingAnchor.constraint(lessThanOrEqualTo: badge.leadingAnchor, constant: -6),
            badge.widthAnchor.constraint(equalToConstant: ChangeGlyph.size),
            badge.heightAnchor.constraint(equalToConstant: ChangeGlyph.size),
            // As far from the row's edge as from its top and bottom, so the badge sits square in its corner.
            badge.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -(24 - ChangeGlyph.size) / 2),
            badge.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(node: PathNode, glyph: ChangeGlyph?) {
        imageView?.image = NSImage(
            systemSymbolName: node.isDirectory ? "folder" : "doc.text",
            accessibilityDescription: node.isDirectory ? "Folder" : "File")
        textField?.stringValue = node.name
        badge.glyph = glyph
        badge.isDimmed = node.isDirectory
        toolTip = glyph?.title
        setAccessibilityHelp(glyph?.title)
    }
}

public import KittyCodecs

// MARK: - Tree Node

public struct TreeNode<Value: Sendable>: Sendable {
    public var value: Value
    public var children: [TreeNode]
    public var isExpanded: Bool

    public init(value: Value, children: [TreeNode] = [], isExpanded: Bool = false) {
        self.value = value
        self.children = children
        self.isExpanded = isExpanded
    }

    public var isLeaf: Bool { children.isEmpty }
}

// MARK: - Tree View

public struct TreeView<Value: Sendable>: View, Sendable {
    public let root: [TreeNode<Value>]
    public let label: @Sendable (Value) -> String
    public var selectedIndex: Int
    public var scrollOffset: Int
    public var showsVerticalScrollIndicator: Bool
    public var style: TreeViewStyle
    public let rowStyle: @Sendable (Value) -> Style
    public let rowSuffix: @Sendable (Value) -> String
    public let rowSuffixStyle: @Sendable (Value) -> Style

    public struct TreeViewStyle: Sendable {
        public var normalStyle: Style
        public var selectedStyle: Style
        public var expandedIcon: String
        public var collapsedIcon: String
        public var leafIcon: String
        public var indent: Int
        public var scrollIndicatorStyle: VerticalScrollIndicatorStyle

        public init(
            normalStyle: Style = .default,
            selectedStyle: Style = Style(inverse: true),
            expandedIcon: String = "▼",
            collapsedIcon: String = "▶",
            leafIcon: String = " ",
            indent: Int = 2,
            scrollIndicatorStyle: VerticalScrollIndicatorStyle = VerticalScrollIndicatorStyle()
        ) {
            self.normalStyle = normalStyle
            self.selectedStyle = selectedStyle
            self.expandedIcon = expandedIcon
            self.collapsedIcon = collapsedIcon
            self.leafIcon = leafIcon
            self.indent = indent
            self.scrollIndicatorStyle = scrollIndicatorStyle
        }
    }

    public init(
        root: [TreeNode<Value>],
        selectedIndex: Int = 0,
        scrollOffset: Int = 0,
        showsVerticalScrollIndicator: Bool = false,
        style: TreeViewStyle = TreeViewStyle(),
        label: @escaping @Sendable (Value) -> String,
        rowStyle: @escaping @Sendable (Value) -> Style = { _ in .default },
        rowSuffix: @escaping @Sendable (Value) -> String = { _ in "" },
        rowSuffixStyle: @escaping @Sendable (Value) -> Style = { _ in .default }
    ) {
        self.root = root
        self.selectedIndex = selectedIndex
        self.scrollOffset = scrollOffset
        self.showsVerticalScrollIndicator = showsVerticalScrollIndicator
        self.style = style
        self.label = label
        self.rowStyle = rowStyle
        self.rowSuffix = rowSuffix
        self.rowSuffixStyle = rowSuffixStyle
    }

    public var body: Never { fatalError() }

    /// Get the flattened visible rows for rendering.
    public func visibleRows() -> [(depth: Int, node: TreeNode<Value>, index: Int)] {
        var rows: [(depth: Int, node: TreeNode<Value>, index: Int)] = []
        var index = 0
        for node in root {
            flatten(node, depth: 0, rows: &rows, index: &index)
        }
        return rows
    }

    private func flatten(
        _ node: TreeNode<Value>,
        depth: Int,
        rows: inout [(depth: Int, node: TreeNode<Value>, index: Int)],
        index: inout Int
    ) {
        rows.append((depth: depth, node: node, index: index))
        index += 1
        if node.isExpanded {
            for child in node.children {
                flatten(child, depth: depth + 1, rows: &rows, index: &index)
            }
        }
    }
}

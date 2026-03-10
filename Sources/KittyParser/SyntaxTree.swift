// MARK: - Syntax Tree

/// An immutable syntax tree produced by parsing.
/// Supports copy-on-write for incremental parsing subtree sharing.
public struct SyntaxTree: Sendable, Equatable {
    public var root: SyntaxNode
    public var source: String

    public init(root: SyntaxNode, source: String) {
        self.root = root
        self.source = source
    }

    /// Walk the tree depth-first, calling the visitor for each node.
    public func walk(_ visitor: (SyntaxNode, Int) -> Bool) {
        walkNode(root, depth: 0, visitor: visitor)
    }

    private func walkNode(_ node: SyntaxNode, depth: Int, visitor: (SyntaxNode, Int) -> Bool) {
        guard visitor(node, depth) else { return }
        for child in node.children {
            walkNode(child, depth: depth + 1, visitor: visitor)
        }
    }

    /// Find the deepest node at the given byte offset.
    public func nodeAt(byteOffset: Int) -> SyntaxNode? {
        findNode(in: root, offset: byteOffset)
    }

    private func findNode(in node: SyntaxNode, offset: Int) -> SyntaxNode? {
        guard node.byteRange.contains(offset) else { return nil }
        for child in node.children {
            if let found = findNode(in: child, offset: offset) {
                return found
            }
        }
        return node
    }
}

// MARK: - Text Edit

/// Describes an edit to the source text, used for incremental parsing.
public struct TextEdit: Sendable, Equatable {
    public var startByte: Int
    public var oldEndByte: Int
    public var newEndByte: Int
    public var startPoint: Point
    public var oldEndPoint: Point
    public var newEndPoint: Point

    public init(
        startByte: Int,
        oldEndByte: Int,
        newEndByte: Int,
        startPoint: Point = .zero,
        oldEndPoint: Point = .zero,
        newEndPoint: Point = .zero
    ) {
        self.startByte = startByte
        self.oldEndByte = oldEndByte
        self.newEndByte = newEndByte
        self.startPoint = startPoint
        self.oldEndPoint = oldEndPoint
        self.newEndPoint = newEndPoint
    }
}

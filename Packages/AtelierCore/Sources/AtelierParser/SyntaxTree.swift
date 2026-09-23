// MARK: - Syntax Tree

/// An immutable syntax tree produced by parsing.
///
/// A class so `deinit` can release deep trees iteratively: destroying nested `SyntaxNode` arrays recursively
/// overflows the thread stack at about 2,000 levels. `@unchecked Sendable` holds because `root` and `source` are
/// set once at init and never mutated.
public final class SyntaxTree: @unchecked Sendable {
    public let root: SyntaxNode
    public let source: String

    public init(root: SyntaxNode, source: String) {
        self.root = root
        self.source = source
    }

    deinit {
        // Children move to an explicit stack before their parent is released, so no destructor recurses.
        var stack: [SyntaxNode] = [root]
        while !stack.isEmpty {
            var node = stack.removeLast()
            stack.append(contentsOf: node.children)
            node.children = []
            for fieldChildren in node.fields.values {
                stack.append(contentsOf: fieldChildren)
            }
            node.fields = [:]
        }
    }

    /// Walk the tree depth-first, calling the visitor for each node.
    public func walk(_ visitor: (SyntaxNode, Int) -> Bool) {
        // Iterative DFS so deep trees don't blow the stack.
        var stack: [(SyntaxNode, Int)] = [(root, 0)]
        while let (node, depth) = stack.popLast() {
            guard visitor(node, depth) else { continue }
            for child in node.children.reversed() {
                stack.append((child, depth + 1))
            }
        }
    }

    /// Find the deepest node at the given byte offset.
    public func nodeAt(byteOffset: Int) -> SyntaxNode? {
        var current = root
        guard current.byteRange.contains(byteOffset) else { return nil }
        // Iterative descent — pick the first child whose range contains
        // the offset, repeat. Avoids unbounded recursion on deep trees.
        outer: while true {
            for child in current.children where child.byteRange.contains(byteOffset) {
                current = child
                continue outer
            }
            return current
        }
    }
}

// MARK: - Equatable

extension SyntaxTree: Equatable {
    /// Structural equality of the sources and the trees.
    public static func == (lhs: SyntaxTree, rhs: SyntaxTree) -> Bool {
        lhs.source == rhs.source && lhs.root == rhs.root
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

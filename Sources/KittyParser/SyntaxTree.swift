// MARK: - Syntax Tree

/// An immutable syntax tree produced by parsing.
///
/// Reference type so that deep ASTs (e.g. large JSON arrays whose grammar
/// rules build right-leaning structure) can be deallocated iteratively in
/// `deinit`. The previous value-typed implementation triggered a recursive
/// destruction chain — each `SyntaxNode` struct dropping its `children:
/// [SyntaxNode]` recursed into the array's element destructors, blowing
/// the 544 KB thread stack at ~2000 levels of nesting and surfacing as
/// SIGBUS with `KERN_PROTECTION_FAILURE` at the stack guard.
///
/// `root` and `source` are `let` (and the class is therefore safely
/// `Sendable` despite the `@unchecked` tag — they're set once at init,
/// the iterative `deinit` doesn't mutate the tree at all, and no
/// reference escapes after dealloc begins). The `@unchecked` only buys
/// the freedom to hold `SyntaxNode` values (a struct whose `children`
/// and `fields` are `var` arrays for parser-internal building).
public final class SyntaxTree: @unchecked Sendable {
    public let root: SyntaxNode
    public let source: String

    public init(root: SyntaxNode, source: String) {
        self.root = root
        self.source = source
    }

    deinit {
        // Iteratively dispose the tree to avoid recursive struct
        // destructors blowing the stack on deeply-nested ASTs. We
        // hand-walk a stack, popping nodes and pushing their children
        // before they fall out of scope — the popped node's own
        // destructor then never recurses, only releases scalars.
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
    /// Structural equality — preserves the previous value-type semantics.
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

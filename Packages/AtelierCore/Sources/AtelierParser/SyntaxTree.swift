import Synchronization

// MARK: - Syntax Tree

/// An immutable syntax tree produced by parsing.
///
/// A class so `deinit` can take the tree apart without recursion: freeing nested `SyntaxNode` arrays recursively
/// overflows a 512 KiB thread stack between 2,000 and 3,000 levels.
public final class SyntaxTree: Sendable {
    /// The root node, a copy sharing the tree's storage. Only the tree frees nodes without recursion: the last holder
    /// of a copy of a deep node frees that node recursively, so keep the tree alive longer than such copies.
    public var root: SyntaxNode { storedRoot.withLock { $0 } }
    public let source: String
    /// How many bytes of `source` lie under error nodes, each byte counted once: how much of the source the parse
    /// could not make sense of.
    public let errorByteCount: Int
    /// Behind a lock only so `deinit` can take the nodes apart while the class stays checked `Sendable`; nothing else
    /// writes it, so the lock is never contended.
    private let storedRoot: Mutex<SyntaxNode>

    /// A tree over `root`, which may be built by hand; its ``errorByteCount`` comes from a walk of `root`.
    /// - Complexity: O(n + e log e) for n nodes, e of them outermost error nodes.
    public convenience init(root: SyntaxNode, source: String) {
        self.init(
            root: root, source: source,
            errorByteCount: Self.errorByteCount(of: root, sourceCount: source.utf8.count))
    }

    /// A tree whose error bytes are already known, as a parse knows them: it counts each error token it pushes.
    init(root: SyntaxNode, source: String, errorByteCount: Int) {
        self.storedRoot = Mutex(root)
        self.source = source
        self.errorByteCount = errorByteCount
    }

    /// The bytes under the outermost error nodes of `root`, clamped to the source, each counted once.
    private static func errorByteCount(of root: SyntaxNode, sourceCount: Int) -> Int {
        var ranges: [Range<Int>] = []
        var pending = [root]
        while let node = pending.popLast() {
            guard node.isError else {
                pending.append(contentsOf: node.children)
                continue
            }
            let range = node.byteRange.clamped(to: 0 ..< sourceCount)
            if !range.isEmpty { ranges.append(range) }
        }
        ranges.sort { $0.lowerBound < $1.lowerBound }
        var count = 0
        var coveredEnd = 0
        for range in ranges where range.upperBound > coveredEnd {
            count += range.upperBound - max(range.lowerBound, coveredEnd)
            coveredEnd = range.upperBound
        }
        return count
    }

    deinit {
        Self.releaseIteratively(
            storedRoot.withLock { root in
                let taken = root
                root = SyntaxNode(type: taken.type)
                return [taken]
            })
    }

    /// Frees `nodes` and every node below them in a loop, so no depth of tree can overflow the stack.
    ///
    /// A node held elsewhere as well is walked but survives: its last owner frees it. A field node that is a copy of
    /// one of its parent's children, as the parser records fields, is freed through that child.
    ///
    /// - Complexity: O(n) in the nodes reachable from `nodes`, a node counting once per path to it, plus, per node,
    ///   its field nodes times its children.
    static func releaseIteratively(_ nodes: consuming [SyntaxNode]) {
        // Sibling lists this loop alone holds, each emptied from its end. A node hands its subtrees to `lists` before
        // it is dropped, so freeing one of its buffers only drops references `lists` still holds.
        var lists = [consume nodes]
        while let last = lists.indices.last {
            guard var node = lists[last].popLast() else {
                lists.removeLast()
                continue
            }
            if !node.fields.isEmpty {
                let fields = node.fields
                node.fields = [:]
                for fieldNodes in fields.values {
                    for fieldNode in fieldNodes
                    where !fieldNode.children.isEmpty
                        && !node.children.contains(where: { $0.children.isTriviallyIdentical(to: fieldNode.children) })
                    {
                        lists.append([fieldNode])
                    }
                }
            }
            if !node.children.isEmpty {
                lists.append(node.children)
                node.children = []
            }
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

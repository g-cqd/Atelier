import Foundation

// MARK: - Point

public struct Point: Sendable, Equatable, Hashable, Comparable {
    public var row: Int
    public var column: Int

    public init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }

    public static let zero = Point(row: 0, column: 0)

    public static func < (lhs: Point, rhs: Point) -> Bool {
        if lhs.row != rhs.row { return lhs.row < rhs.row }
        return lhs.column < rhs.column
    }
}

// MARK: - Syntax Node

/// A node of a syntax tree: a value, whose copies share their children and fields until one of them changes them.
///
/// Freeing a node frees its subtree in a loop, whichever copy is dropped last: a tree, a parse stack, a copy read from
/// ``SyntaxTree/root``, or an array of nodes. Freed recursively, a chain of nodes overflows a 512 KiB thread stack
/// between 2,000 and 3,000 levels.
public struct SyntaxNode: Sendable, Equatable {
    public var type: String
    public var byteRange: Range<Int>
    public var pointRange: Range<Point>
    public var isError: Bool
    public var isExtra: Bool
    public var isNamed: Bool
    /// The node's children and fields; nil for a node with neither, such as a token.
    fileprivate var subtrees: Subtrees?

    public var children: [SyntaxNode] {
        get { subtrees?.children ?? [] }
        _modify { yield &uniqueSubtrees().children }
    }

    public var fields: [String: [SyntaxNode]] {
        get { subtrees?.fields ?? [:] }
        _modify { yield &uniqueSubtrees().fields }
    }

    public init(
        type: String,
        children: [SyntaxNode] = [],
        byteRange: Range<Int> = 0 ..< 0,
        pointRange: Range<Point> = Point.zero ..< Point.zero,
        fields: [String: [SyntaxNode]] = [:],
        isError: Bool = false,
        isExtra: Bool = false,
        isNamed: Bool = true
    ) {
        self.type = type
        self.byteRange = byteRange
        self.pointRange = pointRange
        self.isError = isError
        self.isExtra = isExtra
        self.isNamed = isNamed
        self.subtrees = children.isEmpty && fields.isEmpty ? nil : Subtrees(children: children, fields: fields)
    }

    public static func == (lhs: SyntaxNode, rhs: SyntaxNode) -> Bool {
        lhs.type == rhs.type && lhs.byteRange == rhs.byteRange && lhs.pointRange == rhs.pointRange
            && lhs.isError == rhs.isError && lhs.isExtra == rhs.isExtra && lhs.isNamed == rhs.isNamed
            && (lhs.subtrees === rhs.subtrees || (lhs.children == rhs.children && lhs.fields == rhs.fields))
    }

    /// This node's subtrees, copied first if another node shares them, so a change reaches this node alone.
    private mutating func uniqueSubtrees() -> Subtrees {
        // Checked before binding: the binding is a reference of its own.
        if isKnownUniquelyReferenced(&subtrees), let subtrees { return subtrees }
        let copy = Subtrees(children: children, fields: fields)
        subtrees = copy
        return copy
    }

    /// Moves this node's children and fields to `lists` when no other node shares them, so that dropping the node
    /// frees nothing below it. Shared subtrees stay: their other holder keeps them alive.
    fileprivate mutating func moveUnsharedSubtrees(to lists: inout [[SyntaxNode]]) {
        guard isKnownUniquelyReferenced(&subtrees), let subtrees else { return }
        subtrees.moveContents(to: &lists)
    }

    /// The text content at this node (requires source).
    public func text(from source: String) -> String {
        if let text = source.utf8.withContiguousStorageIfAvailable({ utf8 in
            text(from: utf8)
        }) {
            return text
        }

        let utf8 = Array(source.utf8)
        return utf8.withUnsafeBufferPointer { utf8 in
            text(from: utf8)
        }
    }

    /// Named children only.
    public var namedChildren: [SyntaxNode] {
        children.filter(\.isNamed)
    }

    /// First child with the given field name.
    public func child(forField name: String) -> SyntaxNode? {
        fields[name]?.first
    }

    private func text(from utf8: UnsafeBufferPointer<UInt8>) -> String {
        let lower = min(max(byteRange.lowerBound, 0), utf8.count)
        let upper = min(max(byteRange.upperBound, 0), utf8.count)
        guard lower < upper else { return "" }
        let buf = UnsafeBufferPointer(rebasing: utf8[lower ..< upper])
        return String(bytes: buf, encoding: .utf8) ?? String(decoding: buf, as: UTF8.self)
    }
}

// MARK: - Subtrees

/// A node's children and fields, behind a reference so that the last node to drop them can free them in a loop.
///
/// Mutable only through ``SyntaxNode``, which copies an instance another node shares before changing it, and through
/// its own `deinit`, which runs once nothing else holds it: a shared instance is never written, which is what makes the
/// unchecked `Sendable` sound.
private final class Subtrees: @unchecked Sendable {
    var children: [SyntaxNode]
    var fields: [String: [SyntaxNode]]

    init(children: [SyntaxNode], fields: [String: [SyntaxNode]]) {
        self.children = children
        self.fields = fields
    }

    /// Frees the subtree in a loop: each node the loop drops has handed its own unshared subtrees to the loop first,
    /// so its `deinit` finds nothing to free, and the stack stays a few frames deep whatever the tree's depth.
    ///
    /// A node shared with another holder, as a field shares its child's subtrees or a parse stack shares its nodes
    /// with its forks, is only released: each subtree is taken apart once, by its last holder.
    /// - Complexity: O(n) in the nodes no other holder shares; O(`children.count`) when every child is a leaf.
    deinit {
        guard !fields.isEmpty || children.contains(where: { $0.subtrees != nil }) else { return }
        var lists: [[SyntaxNode]] = []
        moveContents(to: &lists)
        while let last = lists.indices.last {
            guard var node = lists[last].popLast() else {
                lists.removeLast()
                continue
            }
            node.moveUnsharedSubtrees(to: &lists)
        }
    }

    /// Moves the children and each field's nodes to `lists`, leaving this instance empty.
    func moveContents(to lists: inout [[SyntaxNode]]) {
        if !children.isEmpty {
            lists.append(children)
            children = []
        }
        if !fields.isEmpty {
            lists.append(contentsOf: fields.values)
            fields = [:]
        }
    }
}

// MARK: - Parse Error

public enum ParseError: Error, Sendable, Equatable {
    case invalidInput
    case noParseTable
    case parsingFailed(String)
    /// The source holds more tokens than a parse takes, `limit`.
    case tooManyTokens(limit: Int)
    /// The tree would be more than `limit` levels deep, deeper than a parse builds.
    case tooDeep(limit: Int)
    /// The task the parse ran in was cancelled; the parse found it so before the token at `atToken`, counting every
    /// token it read, comments too.
    case cancelled(atToken: Int)
}

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
/// between 2,000 and 3,000 levels. Only a subtree without fields and at most ``maxInlineHeight`` levels tall is freed
/// recursively, a few frames per level, and it costs no allocation of its own: most of a tree's nodes are such.
public struct SyntaxNode: Sendable, Equatable {
    public var type: String
    public var byteRange: Range<Int>
    public var pointRange: Range<Point>
    public var isError: Bool
    public var isExtra: Bool
    public var isNamed: Bool
    /// How many levels an inline subtree has below this node, 0 for a leaf; `UInt8.max` for a shared one.
    fileprivate var inlineHeight: UInt8
    fileprivate var storage: Storage

    /// The most levels a subtree kept inline has below its root: freeing it takes a few frames per level.
    static let maxInlineHeight: UInt8 = 8

    public var children: [SyntaxNode] {
        get {
            switch storage {
                case .inline(let children): children
                case .shared(let subtrees): subtrees.children
            }
        }
        _modify {
            switch storage {
                case .shared:
                    yield &uniqueSubtrees().children
                case .inline(var children):
                    // Released here, so that `children` is unique and changes in place.
                    storage = .inline([])
                    defer { (storage, inlineHeight) = Self.storage(children: children, fields: [:]) }
                    yield &children
            }
        }
    }

    public var fields: [String: [SyntaxNode]] {
        get {
            switch storage {
                case .inline: [:]
                case .shared(let subtrees): subtrees.fields
            }
        }
        _modify {
            switch storage {
                case .shared:
                    yield &uniqueSubtrees().fields
                case .inline(let children):
                    var fields: [String: [SyntaxNode]] = [:]
                    defer {
                        if !fields.isEmpty {
                            (storage, inlineHeight) = Self.storage(children: children, fields: fields)
                        }
                    }
                    yield &fields
            }
        }
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
        (storage, inlineHeight) = Self.storage(children: children, fields: fields)
    }

    /// Where a node with `children` and `fields` keeps them, and its inline height: inline when it has no fields and
    /// its children are inline, at most ``maxInlineHeight`` levels below it; shared otherwise.
    fileprivate static func storage(children: [SyntaxNode], fields: [String: [SyntaxNode]]) -> (Storage, UInt8) {
        if fields.isEmpty {
            var height: UInt8 = 0
            for child in children {
                guard child.inlineHeight < maxInlineHeight else {
                    height = .max
                    break
                }
                height = max(height, child.inlineHeight + 1)
            }
            if height <= maxInlineHeight { return (.inline(children), height) }
        }
        return (.shared(Subtrees(children: children, fields: fields)), .max)
    }

    /// Whether the two nodes have the same attributes, children and fields, compared in a loop: compared recursively,
    /// two chains overflow a 512 KiB thread stack a few thousand levels down.
    /// - Complexity: O(n) in the nodes the two do not share. A pair of shared subtrees reached twice, as a field
    ///   reaches its child's, is compared once: comparing fields and children alike doubles the work at each level a
    ///   field names. An inline subtree has no fields.
    public static func == (lhs: SyntaxNode, rhs: SyntaxNode) -> Bool {
        guard lhs.hasSameAttributes(as: rhs) else { return false }
        // The pairs of subtrees still to compare, below two nodes with the same attributes.
        var pending: [(Storage, Storage)] = []
        if !lhs.storage.isIdentical(to: rhs.storage) { pending.append((lhs.storage, rhs.storage)) }
        var compared: Set<SubtreesPair> = []
        /// Whether the two lists have the same count and their nodes the same attributes, pair by pair; queues the
        /// pairs' subtrees.
        func queue(_ leftNodes: [SyntaxNode], _ rightNodes: [SyntaxNode]) -> Bool {
            guard leftNodes.count == rightNodes.count else { return false }
            for (leftNode, rightNode) in zip(leftNodes, rightNodes) {
                guard leftNode.hasSameAttributes(as: rightNode) else { return false }
                if !leftNode.storage.isIdentical(to: rightNode.storage) {
                    pending.append((leftNode.storage, rightNode.storage))
                }
            }
            return true
        }
        while let (left, right) = pending.popLast() {
            let (leftFields, rightFields) = (left.fields, right.fields)
            guard leftFields.count == rightFields.count else { return false }
            if case .shared(let left) = left, case .shared(let right) = right,
                !compared.insert(SubtreesPair(left: left, right: right)).inserted
            {
                continue
            }
            guard queue(left.children, right.children) else { return false }
            for (name, leftNodes) in leftFields {
                guard let rightNodes = rightFields[name], queue(leftNodes, rightNodes) else { return false }
            }
        }
        return true
    }

    /// Whether the two nodes are alike but for their children and fields.
    private func hasSameAttributes(as other: SyntaxNode) -> Bool {
        type == other.type && byteRange == other.byteRange && pointRange == other.pointRange
            && isError == other.isError && isExtra == other.isExtra && isNamed == other.isNamed
    }

    /// This node, `rewrite` applied to it and to the nodes below it, rebuilt in a loop: rebuilt recursively, a chain
    /// overflows a 512 KiB thread stack a few thousand levels down.
    ///
    /// `rewrite` changes a node's own attributes, never its children or fields, and returns whether the nodes below it
    /// need rewriting too; those of a node it returns false for stay as they are. Shared subtrees reached twice, as a
    /// field reaches its child's, are rebuilt once and stay shared.
    /// - Complexity: O(n) in the nodes rewritten.
    func rewritten(by rewrite: (inout SyntaxNode) -> Bool) -> SyntaxNode {
        var root = self
        guard rewrite(&root), !root.isLeaf else { return root }
        // Each shared subtree's rebuilt copy, and the path from the root to the node being rewritten: one frame per
        // subtree being rebuilt, its current node the one whose subtree the frame above rebuilds.
        var copies: [ObjectIdentifier: (Storage, UInt8)] = [:]
        var frames = [RewriteFrame(root.storage)]
        while let top = frames.indices.last {
            guard var node = frames[top].current else {
                let frame = frames.removeLast()
                let copy = frame.rebuilt
                if let original = frame.original { copies[ObjectIdentifier(original)] = copy }
                guard let parent = frames.indices.last else {
                    (root.storage, root.inlineHeight) = copy
                    return root
                }
                frames[parent].finishCurrent(withStorage: copy)
                continue
            }
            guard rewrite(&node), !node.isLeaf else {
                frames[top].finishCurrent(node)
                continue
            }
            if case .shared(let below) = node.storage, let copy = copies[ObjectIdentifier(below)] {
                (node.storage, node.inlineHeight) = copy
                frames[top].finishCurrent(node)
                continue
            }
            frames[top].replaceCurrent(node)
            frames.append(RewriteFrame(node.storage))
        }
        return root
    }

    /// Whether the node has neither children nor fields, as a token.
    private var isLeaf: Bool {
        if case .inline(let children) = storage { children.isEmpty } else { false }
    }

    /// This node's shared subtrees, copied first if another node shares them, so a change reaches this node alone.
    private mutating func uniqueSubtrees() -> Subtrees {
        guard case .shared(var subtrees) = storage else { preconditionFailure("the node's subtrees are inline") }
        // Released here, so that `subtrees` is the only reference unless another node holds one.
        storage = .inline([])
        if !isKnownUniquelyReferenced(&subtrees) {
            subtrees = Subtrees(children: subtrees.children, fields: subtrees.fields)
        }
        storage = .shared(subtrees)
        return subtrees
    }

    /// Moves this node's shared children and fields to `lists` when no other node shares them, so that dropping the
    /// node frees nothing below it. Shared subtrees another node holds stay: their other holder keeps them alive. An
    /// inline subtree stays too: it is freed recursively, a few levels.
    fileprivate mutating func moveUnsharedSubtrees(to lists: inout [[SyntaxNode]]) {
        guard case .shared(var subtrees) = storage else { return }
        storage = .inline([])
        guard isKnownUniquelyReferenced(&subtrees) else { return }
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

// MARK: - Storage

/// Where a node keeps its children and fields.
private enum Storage {
    /// Children without fields, each inline too, at most ``SyntaxNode/maxInlineHeight`` levels below the node: a
    /// leaf's is empty, and allocates nothing.
    case inline([SyntaxNode])
    /// Any other children and fields, freed in a loop by their last holder.
    case shared(Subtrees)

    var children: [SyntaxNode] {
        switch self {
            case .inline(let children): children
            case .shared(let subtrees): subtrees.children
        }
    }

    var fields: [String: [SyntaxNode]] {
        switch self {
            case .inline: [:]
            case .shared(let subtrees): subtrees.fields
        }
    }

    var isShared: Bool {
        if case .shared = self { true } else { false }
    }

    /// Whether the two hold the same children and fields by identity, as a copy of a node holds its original's.
    func isIdentical(to other: Storage) -> Bool {
        switch (self, other) {
            case (.inline(let left), .inline(let right)): left.isTriviallyIdentical(to: right)
            case (.shared(let left), .shared(let right)): left === right
            default: false
        }
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
        guard !fields.isEmpty || children.contains(where: \.storage.isShared) else { return }
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

/// Two subtrees ``SyntaxNode/==`` has compared, or is comparing, by identity.
private struct SubtreesPair: Hashable {
    let left: ObjectIdentifier
    let right: ObjectIdentifier

    init(left: Subtrees, right: Subtrees) {
        self.left = ObjectIdentifier(left)
        self.right = ObjectIdentifier(right)
    }
}

/// A subtree ``SyntaxNode/rewritten(by:)`` is rebuilding: its children, then each field's nodes, and the node it is
/// at.
private struct RewriteFrame {
    /// The shared subtree being rebuilt; nil for an inline one.
    let original: Subtrees?
    /// The children, then each field's nodes in the order of `names`; rewritten up to the current node.
    private var lists: [[SyntaxNode]]
    private let names: [String]
    private var list = 0
    private var index = 0

    init(_ storage: Storage) {
        if case .shared(let subtrees) = storage { original = subtrees } else { original = nil }
        let fields = storage.fields
        names = Array(fields.keys)
        lists = [storage.children] + names.map { fields[$0] ?? [] }
        skipFinishedLists()
    }

    /// The node to rewrite next, nil once every one is.
    var current: SyntaxNode? { list < lists.count ? lists[list][index] : nil }

    /// The storage of the rewritten nodes, and its inline height.
    var rebuilt: (Storage, UInt8) {
        SyntaxNode.storage(
            children: lists[0], fields: Dictionary(uniqueKeysWithValues: zip(names, lists.dropFirst())))
    }

    /// Replaces the current node with `node`, rewritten but for the subtrees below it, which a frame above rebuilds.
    mutating func replaceCurrent(_ node: SyntaxNode) {
        lists[list][index] = node
    }

    /// Gives the current node, rewritten, the rebuilt `storage`, and moves to the next node.
    mutating func finishCurrent(withStorage storage: (Storage, UInt8)) {
        (lists[list][index].storage, lists[list][index].inlineHeight) = storage
        advance()
    }

    /// Replaces the current node with `node`, rewritten with the subtrees below it, and moves to the next node.
    mutating func finishCurrent(_ node: SyntaxNode) {
        lists[list][index] = node
        advance()
    }

    private mutating func advance() {
        index += 1
        skipFinishedLists()
    }

    private mutating func skipFinishedLists() {
        while list < lists.count, index == lists[list].count {
            list += 1
            index = 0
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

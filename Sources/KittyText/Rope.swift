import Foundation

/// A persistent, value-typed UTF-8 byte rope.
///
/// `Rope` is the lowest layer of the document storage stack. Bytes are stored
/// as a tree of leaves so insertions and deletions cost O(log n) regardless
/// of where they occur. Each subtree caches its byte count and newline count
/// so the line-indexed queries `TextBuffer` exposes (`line(at:)`,
/// `byteOffset(forLine:)`) are also O(log n).
///
/// Value semantics are preserved through copy-on-write: the underlying tree is
/// held by a single reference type that's cloned only when a mutation occurs
/// on a non-uniquely-owned rope.
public struct Rope: Sendable {
    private var storage: Storage

    /// Maximum bytes per leaf chunk. Smaller leaves → deeper tree but cheaper
    /// per-edit memmove inside a leaf. 512 balances tree depth (~log_2(N/512))
    /// against per-leaf work.
    static let maxLeafSize = 512

    // MARK: - Construction

    /// Creates an empty rope.
    public init() {
        storage = Storage(root: .leaf(LeafNode(data: Data(), newlineCount: 0)))
    }

    /// Creates a rope containing the UTF-8 bytes of `string`.
    public init(_ string: String) {
        self.init(bytes: Data(string.utf8))
    }

    /// Creates a rope from raw UTF-8 bytes.
    public init(bytes: Data) {
        storage = Storage(root: Self.buildBalanced(from: bytes))
    }

    // MARK: - Queries

    public var byteCount: Int { storage.root.byteCount }

    /// Number of logical lines. A document with `n` newlines has `n + 1` lines.
    public var lineCount: Int { storage.root.newlineCount + 1 }

    public var text: String {
        var data = Data()
        data.reserveCapacity(byteCount)
        storage.root.appendAllBytes(to: &data)
        return String(decoding: data, as: UTF8.self)
    }

    /// Byte offset of the start of line `line`, or `-1` if out of range.
    public func byteOffset(forLine line: Int) -> Int {
        guard line >= 0, line < lineCount else { return -1 }
        if line == 0 { return 0 }
        return storage.root.byteOffsetAfterNewline(count: line)
    }

    /// Byte range of line `line` excluding its terminating newline.
    public func lineRange(forLine line: Int) -> Range<Int> {
        guard line >= 0, line < lineCount else { return 0..<0 }
        let start = byteOffset(forLine: line)
        if line == lineCount - 1 {
            return start..<byteCount
        }
        let nextStart = byteOffset(forLine: line + 1)
        return start..<(nextStart - 1)
    }

    /// UTF-8-decoded content of line `index`, or `""` if out of range.
    public func line(at index: Int) -> String {
        guard index >= 0, index < lineCount else { return "" }
        let range = lineRange(forLine: index)
        if range.isEmpty { return "" }
        let slice = bytes(in: range)
        return String(decoding: slice, as: UTF8.self)
    }

    /// UTF-8 bytes for the given range, clamped to the rope's bounds.
    public func bytes(in range: Range<Int>) -> Data {
        let clamped = clampRange(range)
        guard clamped.lowerBound < clamped.upperBound else { return Data() }
        var out = Data()
        out.reserveCapacity(clamped.count)
        storage.root.appendBytes(in: clamped, to: &out)
        return out
    }

    // MARK: - Mutation

    public mutating func insert(_ string: String, atByteOffset byteOffset: Int) {
        guard !string.isEmpty else { return }
        ensureUnique()
        let bytes = Data(string.utf8)
        let clamped = max(0, min(byteOffset, byteCount))
        storage.root = storage.root.inserting(bytes, at: clamped)
    }

    public mutating func remove(_ range: Range<Int>) {
        let clamped = clampRange(range)
        guard clamped.lowerBound < clamped.upperBound else { return }
        ensureUnique()
        storage.root = storage.root.removing(clamped)
    }

    public mutating func replace(_ range: Range<Int>, with string: String) {
        let clamped = clampRange(range)
        ensureUnique()
        if clamped.lowerBound < clamped.upperBound {
            storage.root = storage.root.removing(clamped)
        }
        if !string.isEmpty {
            let bytes = Data(string.utf8)
            let insertOffset = max(0, min(clamped.lowerBound, storage.root.byteCount))
            storage.root = storage.root.inserting(bytes, at: insertOffset)
        }
    }

    // MARK: - Internals

    private func clampRange(_ range: Range<Int>) -> Range<Int> {
        let lower = max(0, min(range.lowerBound, byteCount))
        let upper = max(lower, min(range.upperBound, byteCount))
        return lower..<upper
    }

    private mutating func ensureUnique() {
        if !isKnownUniquelyReferenced(&storage) {
            storage = storage.clone()
        }
    }

    /// Builds a balanced tree from a contiguous byte buffer in one pass.
    private static func buildBalanced(from data: Data) -> RopeNode {
        if data.count <= maxLeafSize {
            return .leaf(LeafNode(data: data, newlineCount: countNewlines(in: data)))
        }
        let mid = data.count / 2
        let left = buildBalanced(from: data.subdata(in: 0..<mid))
        let right = buildBalanced(from: data.subdata(in: mid..<data.count))
        return RopeNode.makeBranch(left, right)
    }

    static func countNewlines(in data: Data) -> Int {
        var count = 0
        for byte in data where byte == 0x0A { count += 1 }
        return count
    }
}

// MARK: - Storage (CoW reference type)

extension Rope {
    /// Reference type that wraps the tree root so we can use
    /// `isKnownUniquelyReferenced` for copy-on-write.
    fileprivate final class Storage: @unchecked Sendable {
        var root: RopeNode

        init(root: RopeNode) {
            self.root = root
        }

        func clone() -> Storage {
            Storage(root: root)
        }
    }
}

// MARK: - Node

/// Leaf payload as a class so the indirect-enum heap allocation is explicit
/// and we can rely on standard ARC semantics.
final class LeafNode: @unchecked Sendable {
    let data: Data
    let newlineCount: Int

    init(data: Data, newlineCount: Int) {
        self.data = data
        self.newlineCount = newlineCount
    }
}

/// Branch payload as a class so the tree has explicit reference structure
/// (CoW handled by `Rope.Storage`).
final class BranchNode: @unchecked Sendable {
    let left: RopeNode
    let right: RopeNode
    let byteCount: Int
    let newlineCount: Int

    init(left: RopeNode, right: RopeNode) {
        self.left = left
        self.right = right
        self.byteCount = left.byteCount + right.byteCount
        self.newlineCount = left.newlineCount + right.newlineCount
    }
}

/// Rope node variant. Using class-backed payloads instead of an `indirect enum`
/// gives us deterministic ARC semantics and avoids any subtle CoW interactions
/// of recursive `Sendable indirect enum`s.
enum RopeNode: Sendable {
    case leaf(LeafNode)
    case branch(BranchNode)

    var byteCount: Int {
        switch self {
        case .leaf(let leaf): return leaf.data.count
        case .branch(let branch): return branch.byteCount
        }
    }

    var newlineCount: Int {
        switch self {
        case .leaf(let leaf): return leaf.newlineCount
        case .branch(let branch): return branch.newlineCount
        }
    }

    // MARK: - Reads

    func appendAllBytes(to out: inout Data) {
        switch self {
        case .leaf(let leaf):
            out.append(leaf.data)
        case .branch(let branch):
            branch.left.appendAllBytes(to: &out)
            branch.right.appendAllBytes(to: &out)
        }
    }

    func appendBytes(in range: Range<Int>, to out: inout Data) {
        if range.isEmpty { return }
        switch self {
        case .leaf(let leaf):
            let lower = max(0, range.lowerBound)
            let upper = min(leaf.data.count, range.upperBound)
            if lower < upper {
                out.append(leaf.data.subdata(in: lower..<upper))
            }
        case .branch(let branch):
            let leftCount = branch.left.byteCount
            if range.lowerBound < leftCount {
                let leftUpper = min(leftCount, range.upperBound)
                branch.left.appendBytes(in: range.lowerBound..<leftUpper, to: &out)
            }
            if range.upperBound > leftCount {
                let rightLower = max(0, range.lowerBound - leftCount)
                let rightUpper = range.upperBound - leftCount
                branch.right.appendBytes(in: rightLower..<rightUpper, to: &out)
            }
        }
    }

    /// Byte offset just past the `n`-th newline (= start of line `n`).
    /// Precondition: `n > 0`.
    func byteOffsetAfterNewline(count n: Int) -> Int {
        precondition(n > 0)
        switch self {
        case .leaf(let leaf):
            var seen = 0
            var index = 0
            for byte in leaf.data {
                if byte == 0x0A {
                    seen += 1
                    if seen == n { return index + 1 }
                }
                index += 1
            }
            return leaf.data.count
        case .branch(let branch):
            let leftNewlines = branch.left.newlineCount
            if n <= leftNewlines {
                return branch.left.byteOffsetAfterNewline(count: n)
            }
            return branch.left.byteCount + branch.right.byteOffsetAfterNewline(count: n - leftNewlines)
        }
    }

    // MARK: - Mutations (return new nodes)

    func inserting(_ bytes: Data, at offset: Int) -> RopeNode {
        switch self {
        case .leaf(let leaf):
            var data = leaf.data
            data.insert(contentsOf: bytes, at: offset)
            return RopeNode.fromLeafData(data)
        case .branch(let branch):
            let leftCount = branch.left.byteCount
            if offset <= leftCount {
                let newLeft = branch.left.inserting(bytes, at: offset)
                return RopeNode.makeBranch(newLeft, branch.right)
            } else {
                let newRight = branch.right.inserting(bytes, at: offset - leftCount)
                return RopeNode.makeBranch(branch.left, newRight)
            }
        }
    }

    func removing(_ range: Range<Int>) -> RopeNode {
        if range.isEmpty { return self }
        switch self {
        case .leaf(let leaf):
            var data = leaf.data
            let lower = max(0, range.lowerBound)
            let upper = min(data.count, range.upperBound)
            if lower < upper {
                data.removeSubrange(lower..<upper)
            }
            return RopeNode.fromLeafData(data)
        case .branch(let branch):
            let leftCount = branch.left.byteCount
            let leftUpper = min(leftCount, range.upperBound)
            let newLeft: RopeNode
            if range.lowerBound < leftUpper {
                newLeft = branch.left.removing(range.lowerBound..<leftUpper)
            } else {
                newLeft = branch.left
            }
            let newRight: RopeNode
            if range.upperBound > leftCount {
                let rightLower = max(0, range.lowerBound - leftCount)
                let rightUpper = range.upperBound - leftCount
                newRight = branch.right.removing(rightLower..<rightUpper)
            } else {
                newRight = branch.right
            }
            return RopeNode.mergeOrBranch(newLeft, newRight)
        }
    }

    // MARK: - Constructors

    static func fromLeafData(_ data: Data) -> RopeNode {
        if data.count <= Rope.maxLeafSize {
            return makeLeaf(data)
        }
        return splitLargeLeaf(data)
    }

    private static func splitLargeLeaf(_ data: Data) -> RopeNode {
        if data.count <= Rope.maxLeafSize {
            return makeLeaf(data)
        }
        let mid = data.count / 2
        let leftData = data.subdata(in: 0..<mid)
        let rightData = data.subdata(in: mid..<data.count)
        return makeBranch(splitLargeLeaf(leftData), splitLargeLeaf(rightData))
    }

    static func makeLeaf(_ data: Data) -> RopeNode {
        .leaf(LeafNode(data: data, newlineCount: Rope.countNewlines(in: data)))
    }

    /// Combine two subtrees, collapsing empty leaves and merging tiny adjacent
    /// leaves so the tree doesn't accumulate dead structure after deletes.
    static func mergeOrBranch(_ left: RopeNode, _ right: RopeNode) -> RopeNode {
        if case .leaf(let l) = left, l.data.isEmpty { return right }
        if case .leaf(let r) = right, r.data.isEmpty { return left }
        if case .leaf(let l) = left, case .leaf(let r) = right,
            l.data.count + r.data.count <= Rope.maxLeafSize {
            return makeLeaf(l.data + r.data)
        }
        return makeBranch(left, right)
    }

    static func makeBranch(_ left: RopeNode, _ right: RopeNode) -> RopeNode {
        if case .leaf(let l) = left, l.data.isEmpty { return right }
        if case .leaf(let r) = right, r.data.isEmpty { return left }
        return .branch(BranchNode(left: left, right: right))
    }
}

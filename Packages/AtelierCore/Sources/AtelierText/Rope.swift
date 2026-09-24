public import Foundation
import Synchronization

// The persistent tree and its storage share one file; the size exception is tracked in g-cqd/Atelier#1.
// swiftlint:disable file_length

/// A persistent, value-typed UTF-8 byte rope.
///
/// `Rope` is the lowest layer of the document storage stack. Bytes are stored
/// as a tree of leaves so localized edits touch O(log n) branches plus the bytes
/// changed. Each subtree caches its byte count and newline count
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
        storage = Storage(root: Self.buildBalanced(from: bytes, in: bytes.startIndex ..< bytes.endIndex))
    }

    // MARK: - Queries

    public var byteCount: Int { storage.root.byteCount }

    /// Number of logical lines. A document with `n` newlines has `n + 1` lines.
    public var lineCount: Int { storage.root.newlineCount + 1 }

    public var text: String {
        if let cached = storage.cachedText { return cached }
        var data = Data()
        data.reserveCapacity(byteCount)
        storage.root.appendAllBytes(to: &data)
        let result = String(decoding: data, as: UTF8.self)
        storage.cachedText = result
        return result
    }

    /// Materializes every line as a `[String]` in a single tree walk.
    ///
    /// Faster than calling `line(at:)` in a loop because it visits each leaf
    /// exactly once instead of walking from the root for every line. The
    /// result is memoized on the CoW storage and invalidated on mutation. A cold read costs O(document bytes).
    public var allLines: [String] {
        if let cached = storage.cachedLines { return cached }
        var lines: [String] = []
        lines.reserveCapacity(lineCount)
        var current = Data()
        storage.root.collectLines(into: &lines, current: &current)
        lines.append(String(decoding: current, as: UTF8.self))
        storage.cachedLines = lines
        return lines
    }

    /// A hash of the rope's bytes as its leaves hold them: equal bytes split into different leaves can hash apart.
    /// Seeded per process, so it must not be persisted.
    /// - Complexity: O(1): each node caches its hash when built, so an edit rehashes only its O(log n) path.
    public var contentHash: Int {
        var hasher = Hasher()
        hasher.combine(byteCount)
        hasher.combine(lineCount)
        hasher.combine(storage.root.nodeHash)
        return hasher.finalize()
    }

    /// Byte offset of the start of line `line`, or `-1` if out of range.
    public func byteOffset(forLine line: Int) -> Int {
        guard line >= 0, line < lineCount else { return -1 }
        if line == 0 { return 0 }
        return storage.root.byteOffsetAfterNewline(count: line)
    }

    /// Drops this rope's cached `text` and `lines`, leaving the tree untouched, so an undo snapshot does not keep
    /// multi-megabyte strings resident. The storage is made unique first, so a rope sharing it keeps its caches.
    public mutating func invalidateSnapshotCaches() {
        ensureUnique()
        storage.invalidateCaches()
    }

    /// Test-only probe — returns `true` when neither `cachedText` nor
    /// `cachedLines` is currently materialised on the storage. Used by
    /// `BufferEditHistoryTests` to pin the cache-drop invariant of
    /// `recordChange`.
    var _testSnapshotCachesAreEmpty: Bool {
        storage.cachedText == nil && storage.cachedLines == nil
    }

    var _testTreeShape: (height: Int, leafCount: Int) {
        (storage.root.height, storage.root.leafCount)
    }

    var _testAllNodesBalanced: Bool { storage.root._testIsAVL }

    /// Byte range of line `line` excluding its terminating newline.
    public func lineRange(forLine line: Int) -> Range<Int> {
        guard line >= 0, line < lineCount else { return 0 ..< 0 }
        let start = byteOffset(forLine: line)
        if line == lineCount - 1 {
            return start ..< byteCount
        }
        let nextStart = byteOffset(forLine: line + 1)
        return start ..< (nextStart - 1)
    }

    /// UTF-8-decoded content of line `index`, or `""` if out of range.
    /// - Complexity: O(log n + line length) when the lines cache is cold; the branches' newline counts locate the
    ///   line without scanning the bytes before it.
    public func line(at index: Int) -> String {
        guard index >= 0, index < lineCount else { return "" }
        // Fast path: if the lines array is already cached on storage we hit
        // it in O(1) without walking the tree.
        if let cached = storage.cachedLines {
            return cached[index]
        }
        var remainingNewlines = index
        var foundStart = false
        var finished = false
        var data = Data()
        storage.root.appendLine(
            after: &remainingNewlines, foundStart: &foundStart, finished: &finished, to: &data)
        return String(decoding: data, as: UTF8.self)
    }

    /// The lines with indices in `range`, clamped to the rope, without the terminating newlines.
    /// - Complexity: O(log n + bytes of the lines) when the lines cache is cold: one ranged byte read, split once.
    public func lines(in range: Range<Int>) -> [String] {
        let clamped = range.clamped(to: 0 ..< lineCount)
        guard !clamped.isEmpty else { return [] }
        if let cached = storage.cachedLines {
            return Array(cached[clamped])
        }
        let start = lineRange(forLine: clamped.lowerBound).lowerBound
        let end = lineRange(forLine: clamped.upperBound - 1).upperBound
        let data = bytes(in: start ..< end)
        var lines: [String] = []
        lines.reserveCapacity(clamped.count)
        var lineStart = data.startIndex
        for index in data.indices where data[index] == 0x0A {
            lines.append(String(decoding: data[lineStart ..< index], as: UTF8.self))
            lineStart = index + 1
        }
        lines.append(String(decoding: data[lineStart...], as: UTF8.self))
        return lines
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

    // MARK: - Line editing

    /// Replaces line `lineIndex` with `value` and drops any materialized line snapshot.
    public mutating func replaceLine(at lineIndex: Int, with value: String) {
        guard lineIndex >= 0, lineIndex < lineCount else { return }
        replace(lineRange(forLine: lineIndex), with: value)
    }

    /// Inserts a new line containing `value` at logical position `lineIndex`.
    /// Drops any materialized line snapshot.
    public mutating func insertLine(_ value: String, at lineIndex: Int) {
        guard lineIndex >= 0, lineIndex <= lineCount else { return }

        if lineIndex == lineCount {
            insert("\n" + value, atByteOffset: byteCount)
        } else {
            let offset = byteOffset(forLine: lineIndex)
            insert(value + "\n", atByteOffset: offset)
        }
    }

    /// Removes line `lineIndex` and drops any materialized line snapshot.
    @discardableResult
    public mutating func removeLine(at lineIndex: Int) -> String {
        ensureUnique()
        guard lineIndex >= 0, lineIndex < lineCount else { return "" }
        let removed = line(at: lineIndex)
        let count = lineCount

        if count == 1 {
            storage.root = .leaf(LeafNode(data: Data(), newlineCount: 0))
            return removed
        }

        if lineIndex == count - 1 {
            let lineStart = byteOffset(forLine: lineIndex)
            remove((lineStart - 1) ..< byteCount)
        } else {
            let lineStart = byteOffset(forLine: lineIndex)
            let nextStart = byteOffset(forLine: lineIndex + 1)
            remove(lineStart ..< nextStart)
        }

        return removed
    }

    // MARK: - Internals

    private func clampRange(_ range: Range<Int>) -> Range<Int> {
        let lower = max(0, min(range.lowerBound, byteCount))
        let upper = max(lower, min(range.upperBound, byteCount))
        return lower ..< upper
    }

    private mutating func ensureUnique() {
        if !isKnownUniquelyReferenced(&storage) {
            storage = storage.clone()
        }
    }

    /// Builds a balanced tree from a contiguous byte buffer in one pass.
    private static func buildBalanced(from data: Data, in range: Range<Int>) -> RopeNode {
        if range.count <= maxLeafSize {
            return RopeNode.makeLeaf(data.subdata(in: range))
        }
        let mid = range.lowerBound + range.count / 2
        let left = buildBalanced(from: data, in: range.lowerBound ..< mid)
        let right = buildBalanced(from: data, in: mid ..< range.upperBound)
        return RopeNode.makeBranch(left, right)
    }

    static func countNewlines(in data: Data) -> Int {
        let bytes = data.span
        var count = 0
        for index in bytes.indices where bytes[index] == 0x0A { count &+= 1 }
        return count
    }
}

// MARK: - Storage (CoW reference type)

extension Rope {
    /// Reference type that wraps the tree root so we can use
    /// `isKnownUniquelyReferenced` for copy-on-write.
    ///
    /// Holds lazy caches of the materialized text and line array; a mutation
    /// clones a shared storage, whose caches start empty, or invalidates them
    /// when the storage is uniquely held.
    fileprivate final class Storage: @unchecked Sendable {
        /// Written only while the storage is uniquely referenced (`ensureUnique()` precedes every mutation), so a
        /// shared storage is read-only here; the caches below are the one thing readers write, and they go
        /// through a lock so two threads materialising the same rope cannot tear each other's store.
        var root: RopeNode {
            didSet { invalidateCaches() }
        }
        private struct Caches {
            var text: String?
            var lines: [String]?
        }
        private let caches = Mutex(Caches())
        var cachedText: String? {
            get { caches.withLock { $0.text } }
            set { caches.withLock { $0.text = newValue } }
        }
        var cachedLines: [String]? {
            get { caches.withLock { $0.lines } }
            set { caches.withLock { $0.lines = newValue } }
        }
        init(root: RopeNode) {
            self.root = root
        }

        func clone() -> Storage {
            Storage(root: root)
        }

        func invalidateCaches() {
            caches.withLock {
                $0.text = nil
                $0.lines = nil
            }
        }
    }
}

// MARK: - Node

/// Leaf payload as a class so the indirect-enum heap allocation is explicit
/// and we can rely on standard ARC semantics.
final class LeafNode: @unchecked Sendable {
    let data: Data
    let newlineCount: Int
    /// Per-leaf hash computed once at construction. Lets `Rope.contentHash`
    /// run in O(1) after the rope settles — see `RopeNode.nodeHash`.
    let leafHash: Int

    init(data: Data, newlineCount: Int) {
        self.data = data
        self.newlineCount = newlineCount
        var hasher = Hasher()
        hasher.combine(data)
        self.leafHash = hasher.finalize()
    }
}

/// Branch payload as a class so the tree has explicit reference structure
/// (CoW handled by `Rope.Storage`).
final class BranchNode: @unchecked Sendable {
    let left: RopeNode
    let right: RopeNode
    let byteCount: Int
    let newlineCount: Int
    let height: Int
    let leafCount: Int
    /// Per-branch hash combined from `(left.nodeHash, right.nodeHash)` at
    /// construction. Mutations produce new branches whose hash compute is
    /// O(1) per node — total per-edit hash cost is bounded by the depth of
    /// the path from the mutated leaf to the root (O(log N)).
    let branchHash: Int

    init(left: RopeNode, right: RopeNode) {
        self.left = left
        self.right = right
        self.byteCount = left.byteCount + right.byteCount
        self.newlineCount = left.newlineCount + right.newlineCount
        self.height = max(left.height, right.height) + 1
        self.leafCount = left.leafCount + right.leafCount
        var hasher = Hasher()
        hasher.combine(left.nodeHash)
        hasher.combine(right.nodeHash)
        self.branchHash = hasher.finalize()
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

    var height: Int {
        switch self {
            case .leaf: 1
            case .branch(let branch): branch.height
        }
    }

    var leafCount: Int {
        switch self {
            case .leaf: 1
            case .branch(let branch): branch.leafCount
        }
    }

    var _testIsAVL: Bool {
        switch self {
            case .leaf: true
            case .branch(let branch):
                abs(branch.left.height - branch.right.height) <= 1
                    && branch.height == max(branch.left.height, branch.right.height) + 1
                    && branch.byteCount == branch.left.byteCount + branch.right.byteCount
                    && branch.newlineCount == branch.left.newlineCount + branch.right.newlineCount
                    && branch.left._testIsAVL && branch.right._testIsAVL
        }
    }

    /// Precomputed per-node hash. Dispatches to the leaf or branch payload's
    /// stored hash so `Rope.contentHash` doesn't have to walk the tree on
    /// every read.
    var nodeHash: Int {
        switch self {
            case .leaf(let leaf): return leaf.leafHash
            case .branch(let branch): return branch.branchHash
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

    /// Walks the tree once, accumulating bytes between newlines into `current`
    /// and flushing decoded lines into `lines`. The final line stays in
    /// `current` so the caller can decide whether to append a trailing entry.
    func collectLines(into lines: inout [String], current: inout Data) {
        switch self {
            case .leaf(let leaf):
                let bytes = leaf.data
                let span = bytes.span
                var start = bytes.startIndex
                for offset in span.indices where span[offset] == 0x0A {
                    let split = bytes.startIndex + offset
                    if start < split {
                        current.append(bytes[start ..< split])
                    }
                    lines.append(String(decoding: current, as: UTF8.self))
                    current.removeAll(keepingCapacity: true)
                    start = bytes.index(after: split)
                }
                if start < bytes.endIndex {
                    current.append(bytes[start ..< bytes.endIndex])
                }
            case .branch(let branch):
                branch.left.collectLines(into: &lines, current: &current)
                branch.right.collectLines(into: &lines, current: &current)
        }
    }

    /// Skips whole subtrees until the requested line and copies only its bytes.
    func appendLine(
        after remainingNewlines: inout Int, foundStart: inout Bool, finished: inout Bool, to out: inout Data
    ) {
        if finished { return }
        if !foundStart, remainingNewlines > newlineCount {
            remainingNewlines -= newlineCount
            return
        }
        switch self {
            case .leaf(let leaf):
                let bytes = leaf.data.span
                var start = foundStart ? 0 : nil
                for index in bytes.indices {
                    let byte = bytes[index]
                    if !foundStart {
                        guard remainingNewlines == 0 else {
                            if byte == 0x0A { remainingNewlines -= 1 }
                            continue
                        }
                        foundStart = true
                        start = index
                    }
                    if byte == 0x0A {
                        if let start, start < index {
                            out.append(leaf.data[start ..< index])
                        }
                        finished = true
                        return
                    }
                }
                if let start, start < bytes.count {
                    out.append(leaf.data[start ..< bytes.count])
                }
            case .branch(let branch):
                branch.left.appendLine(
                    after: &remainingNewlines, foundStart: &foundStart, finished: &finished, to: &out)
                branch.right.appendLine(
                    after: &remainingNewlines, foundStart: &foundStart, finished: &finished, to: &out)
        }
    }

    func appendBytes(in range: Range<Int>, to out: inout Data) {
        if range.isEmpty { return }
        switch self {
            case .leaf(let leaf):
                let lower = max(0, range.lowerBound)
                let upper = min(leaf.data.count, range.upperBound)
                if lower < upper {
                    out.append(leaf.data.subdata(in: lower ..< upper))
                }
            case .branch(let branch):
                let leftCount = branch.left.byteCount
                if range.lowerBound < leftCount {
                    let leftUpper = min(leftCount, range.upperBound)
                    branch.left.appendBytes(in: range.lowerBound ..< leftUpper, to: &out)
                }
                if range.upperBound > leftCount {
                    let rightLower = max(0, range.lowerBound - leftCount)
                    let rightUpper = range.upperBound - leftCount
                    branch.right.appendBytes(in: rightLower ..< rightUpper, to: &out)
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
                let bytes = leaf.data.span
                for index in bytes.indices where bytes[index] == 0x0A {
                    seen += 1
                    if seen == n { return index + 1 }
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
                guard offset <= leftCount else {
                    let newRight = branch.right.inserting(bytes, at: offset - leftCount)
                    return RopeNode.join(branch.left, newRight)
                }
                let newLeft = branch.left.inserting(bytes, at: offset)
                return RopeNode.join(newLeft, branch.right)
        }
    }

    func removing(_ range: Range<Int>) -> RopeNode {
        if range.isEmpty { return self }
        if range.lowerBound <= 0, range.upperBound >= byteCount {
            return .leaf(LeafNode(data: Data(), newlineCount: 0))
        }
        switch self {
            case .leaf(let leaf):
                var data = leaf.data
                let lower = max(0, range.lowerBound)
                let upper = min(data.count, range.upperBound)
                if lower < upper {
                    data.removeSubrange(lower ..< upper)
                }
                return RopeNode.fromLeafData(data)
            case .branch(let branch):
                let leftCount = branch.left.byteCount
                let leftUpper = min(leftCount, range.upperBound)
                let newLeft: RopeNode
                if range.lowerBound < leftUpper {
                    newLeft = branch.left.removing(range.lowerBound ..< leftUpper)
                } else {
                    newLeft = branch.left
                }
                let newRight: RopeNode
                if range.upperBound > leftCount {
                    let rightLower = max(0, range.lowerBound - leftCount)
                    let rightUpper = range.upperBound - leftCount
                    newRight = branch.right.removing(rightLower ..< rightUpper)
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
        return splitLargeLeaf(data, in: 0 ..< data.count)
    }

    private static func splitLargeLeaf(_ data: Data, in range: Range<Int>) -> RopeNode {
        if range.count <= Rope.maxLeafSize {
            return makeLeaf(data.subdata(in: range))
        }
        let mid = range.lowerBound + range.count / 2
        return makeBranch(
            splitLargeLeaf(data, in: range.lowerBound ..< mid),
            splitLargeLeaf(data, in: mid ..< range.upperBound))
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
            l.data.count + r.data.count <= Rope.maxLeafSize
        {
            return makeLeaf(l.data + r.data)
        }
        return join(left, right)
    }

    /// Joins AVL subtrees whose heights can differ by more than one after an edit.
    static func join(_ left: RopeNode, _ right: RopeNode) -> RopeNode {
        if case .leaf(let leaf) = left, leaf.data.isEmpty { return right }
        if case .leaf(let leaf) = right, leaf.data.isEmpty { return left }
        if left.height > right.height + 1, case .branch(let branch) = left {
            return balance(branch.left, join(branch.right, right))
        }
        if right.height > left.height + 1, case .branch(let branch) = right {
            return balance(join(left, branch.left), branch.right)
        }
        return makeBranch(left, right)
    }

    private static func balance(_ left: RopeNode, _ right: RopeNode) -> RopeNode {
        if left.height > right.height + 1, case .branch(let branch) = left {
            if branch.left.height >= branch.right.height {
                return makeBranch(branch.left, makeBranch(branch.right, right))
            }
            if case .branch(let middle) = branch.right {
                return makeBranch(
                    makeBranch(branch.left, middle.left), makeBranch(middle.right, right))
            }
        }
        if right.height > left.height + 1, case .branch(let branch) = right {
            if branch.right.height >= branch.left.height {
                return makeBranch(makeBranch(left, branch.left), branch.right)
            }
            if case .branch(let middle) = branch.left {
                return makeBranch(
                    makeBranch(left, middle.left), makeBranch(middle.right, branch.right))
            }
        }
        return makeBranch(left, right)
    }

    static func makeBranch(_ left: RopeNode, _ right: RopeNode) -> RopeNode {
        if case .leaf(let l) = left, l.data.isEmpty { return right }
        if case .leaf(let r) = right, r.data.isEmpty { return left }
        return .branch(BranchNode(left: left, right: right))
    }
}

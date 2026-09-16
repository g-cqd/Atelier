public import Foundation

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
    /// result is memoized on the CoW storage and invalidated on mutation.
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

    /// Stable hash of the rope's content. **O(1) per read** after the
    /// rope has settled — the tree carries per-node hashes precomputed at
    /// construction, so every read just combines `(byteCount, lineCount,
    /// root.nodeHash)`.
    ///
    /// Per-edit cost is bounded by the depth of the mutation path: every
    /// new `BranchNode` produced by `inserting` / `removing` / `replace`
    /// runs its own O(1) hash combine in `init` from its children's
    /// already-cached hashes. The leaf that was mutated computes its hash
    /// once in `LeafNode.init`. Total work per edit: O(log N).
    ///
    /// Useful for change-detection paths (undo/redo invalidation, dirty
    /// tracking) where the full lines-array hash would otherwise dominate
    /// per-edit time on large files. Within a single process run the value
    /// is deterministic; across runs `Hasher`'s seed randomises so values
    /// are not stable for serialisation.
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

    /// Drops the storage's cached `text` / `lines` / `contentHash` without
    /// touching `root`. Used by `BufferEditHistory` immediately before pushing
    /// a snapshot onto the undo stack — a long-lived snapshot would otherwise
    /// keep multi-megabyte `cachedText` and `cachedLines` strings resident
    /// even though no consumer ever reads from the snapshot's rope directly.
    /// The next read on the live document pays the materialisation cost
    /// once; subsequent reads are O(1) again. Tree structure and per-node
    /// metadata (byte counts, newline counts) are unaffected.
    ///
    /// Audit B.5/F2 — clones storage first (`ensureUnique`) so the
    /// invalidation operates on the snapshot's *own* storage instance.
    /// Without this, immediately after `activeBufferSnapshot()` (before
    /// the next mutation triggers CoW) the snapshot's `storage`
    /// reference is the same object as the live document's, and
    /// clearing its caches would nuke the live document's
    /// `cachedText`/`cachedLines` too — re-introducing per-keystroke
    /// rebuild cost. Post-clone, the snapshot owns a private storage
    /// header (cheap — just a class instance + same root reference;
    /// the tree itself is structurally shared until a real mutation).
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
        // Fast path: if the lines array is already cached on storage we hit
        // it in O(1) without walking the tree.
        if let cached = storage.cachedLines {
            return cached[index]
        }
        var out = Data()
        storage.root.appendLineBytes(at: index, to: &out)
        return String(decoding: out, as: UTF8.self)
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

    // MARK: - Cache-aware editing

    /// Replaces line `lineIndex` with `value` and, if the rope had a
    /// materialized `lines` cache before the edit and the line count is
    /// unchanged, patches the cache in place so the next read stays O(1).
    public mutating func replaceLine(at lineIndex: Int, with value: String) {
        guard lineIndex >= 0, lineIndex < lineCount else { return }
        let range = lineRange(forLine: lineIndex)
        let cacheBefore = storage.cachedLines
        let countBefore = lineCount
        replace(range, with: value)
        if let cache = cacheBefore,
            countBefore == lineCount,
            !value.contains("\n"),
            cache.count == lineCount {
            var patched = cache
            patched[lineIndex] = value
            storage.cachedLines = patched
        }
    }

    /// Inserts a new line containing `value` at logical position `lineIndex`.
    /// Patches the lines cache in place if it was already materialized.
    public mutating func insertLine(_ value: String, at lineIndex: Int) {
        guard lineIndex >= 0, lineIndex <= lineCount else { return }
        let cacheBefore = storage.cachedLines
        let payload = value.contains("\n") ? nil : value

        if lineIndex == lineCount {
            insert("\n" + value, atByteOffset: byteCount)
        } else {
            let offset = byteOffset(forLine: lineIndex)
            insert(value + "\n", atByteOffset: offset)
        }

        if let cache = cacheBefore, let payload {
            var patched = cache
            patched.insert(payload, at: lineIndex)
            if patched.count == lineCount {
                storage.cachedLines = patched
            }
        }
    }

    /// Removes line `lineIndex`. Patches the lines cache in place if present.
    @discardableResult
    public mutating func removeLine(at lineIndex: Int) -> String {
        guard lineIndex >= 0, lineIndex < lineCount else { return "" }
        let removed = line(at: lineIndex)
        let cacheBefore = storage.cachedLines
        let count = lineCount

        if count == 1 {
            storage.root = .leaf(LeafNode(data: Data(), newlineCount: 0))
            storage.cachedLines = [""]
            storage.cachedText = ""
            return removed
        }

        if lineIndex == count - 1 {
            let lineStart = byteOffset(forLine: lineIndex)
            remove((lineStart - 1)..<byteCount)
        } else {
            let lineStart = byteOffset(forLine: lineIndex)
            let nextStart = byteOffset(forLine: lineIndex + 1)
            remove(lineStart..<nextStart)
        }

        if let cache = cacheBefore, cache.count == count {
            var patched = cache
            patched.remove(at: lineIndex)
            if patched.count == lineCount {
                storage.cachedLines = patched
            }
        }
        return removed
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
        data.count(where: { $0 == 0x0A })
    }
}

// MARK: - Storage (CoW reference type)

extension Rope {
    /// Reference type that wraps the tree root so we can use
    /// `isKnownUniquelyReferenced` for copy-on-write.
    ///
    /// Holds lazy caches for the materialized text, the line array, and a
    /// content hash — all expensive to recompute and frequently re-read
    /// between edits. Each mutation goes through `clone()` (which starts with
    /// empty caches) or directly through `invalidateCaches()` when storage is
    /// uniquely held.
    fileprivate final class Storage: @unchecked Sendable {
        var root: RopeNode {
            didSet { invalidateCaches() }
        }
        var cachedText: String?
        var cachedLines: [String]?
        init(root: RopeNode) {
            self.root = root
        }

        func clone() -> Storage {
            Storage(root: root)
        }

        func invalidateCaches() {
            cachedText = nil
            cachedLines = nil
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

    /// Reads the UTF-8 bytes of the `index`-th line into `out`, excluding any
    /// terminating newline. Single tree walk: descends to the leaf containing
    /// the line start, then collects bytes forward across leaves until it
    /// finds the terminator (or end of document).
    func appendLineBytes(at index: Int, to out: inout Data) {
        var lineRemaining = index
        var collecting = false
        // Returns true to continue walking, false to stop.
        @discardableResult
        func walk(_ node: RopeNode) -> Bool {
            switch node {
            case .leaf(let leaf):
                let bytes = leaf.data
                var idx = bytes.startIndex
                if !collecting {
                    // Need to skip `lineRemaining` newlines to reach the target line.
                    while idx < bytes.endIndex, lineRemaining > 0 {
                        if bytes[idx] == 0x0A {
                            lineRemaining -= 1
                        }
                        idx = bytes.index(after: idx)
                    }
                    if lineRemaining > 0 { return true }
                    collecting = true
                }
                // Collect bytes until the next newline.
                let start = idx
                while idx < bytes.endIndex, bytes[idx] != 0x0A {
                    idx = bytes.index(after: idx)
                }
                if start < idx {
                    out.append(bytes[start..<idx])
                }
                // Hit a newline → done.
                if idx < bytes.endIndex { return false }
                return true
            case .branch(let branch):
                if !walk(branch.left) { return false }
                return walk(branch.right)
            }
        }
        _ = walk(self)
    }

    /// Walks the tree once, accumulating bytes between newlines into `current`
    /// and flushing decoded lines into `lines`. The final line stays in
    /// `current` so the caller can decide whether to append a trailing entry.
    func collectLines(into lines: inout [String], current: inout Data) {
        switch self {
        case .leaf(let leaf):
            let bytes = leaf.data
            var start = bytes.startIndex
            for (offset, byte) in bytes.enumerated() {
                if byte == 0x0A {
                    let split = bytes.index(bytes.startIndex, offsetBy: offset)
                    if start < split {
                        current.append(bytes[start..<split])
                    }
                    lines.append(String(decoding: current, as: UTF8.self))
                    current.removeAll(keepingCapacity: true)
                    start = bytes.index(after: split)
                }
            }
            if start < bytes.endIndex {
                current.append(bytes[start..<bytes.endIndex])
            }
        case .branch(let branch):
            branch.left.collectLines(into: &lines, current: &current)
            branch.right.collectLines(into: &lines, current: &current)
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

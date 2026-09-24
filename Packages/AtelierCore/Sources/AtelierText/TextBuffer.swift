import Foundation

/// Line-indexed text buffer used by the editor.
///
/// Internally backed by a UTF-8 byte ``Rope`` so insertions and deletions —
/// cost O(log n) in the number of leaves plus the bytes changed. Line metadata is cached in
/// the rope's tree, so line lookups are also O(log n).
///
/// The API is line-oriented, indexed by `(row, col)`.
public struct TextBuffer: Sendable {
    private var rope: Rope

    public var lineCount: Int { rope.lineCount }

    /// Materializes every line as a `[String]` in a single rope walk.
    ///
    /// The cold read costs O(document bytes); the result stays memoized inside
    /// the rope's storage until the next mutation. Subsequent reads are O(1).
    public var lines: [String] {
        get { rope.allLines }
        set {
            let normalized = newValue.isEmpty ? [""] : newValue
            rope = Rope(normalized.joined(separator: "\n"))
        }
    }

    public var isEmpty: Bool {
        rope.lineCount == 1 && rope.line(at: 0).isEmpty
    }

    public static func splitLines(from content: String) -> [String] {
        if content.isEmpty {
            return [""]
        }
        return content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    public init(_ content: String = "") {
        rope = Rope(content)
    }

    public init(lines: [String]) {
        let normalized = lines.isEmpty ? [""] : lines
        rope = Rope(normalized.joined(separator: "\n"))
    }

    /// Returns the line at the given logical index, or an empty string if out of bounds.
    public func line(at index: Int) -> String {
        rope.line(at: index)
    }

    /// Replaces the line at `index` with `value`.
    public mutating func setLine(at index: Int, to value: String) {
        rope.replaceLine(at: index, with: value)
    }

    /// Inserts `line` as a new line at logical position `index`.
    ///
    /// `index == lineCount` appends. Insertion is O(log n).
    public mutating func insertLine(_ line: String, at index: Int) {
        rope.insertLine(line, at: index)
    }

    /// Removes the line at `index`, returning its previous content.
    @discardableResult
    public mutating func removeLine(at index: Int) -> String {
        rope.removeLine(at: index)
    }

    /// Reconstructs the full text by joining lines with newlines.
    public var text: String {
        rope.text
    }

    /// The rope's ``Rope/contentHash``: O(1), and sensitive to how the bytes are split into leaves.
    public var contentHash: Int {
        rope.contentHash
    }

    /// Drops the underlying rope's cached `text` and `lines`, so an undo snapshot does not retain multi-megabyte
    /// strings; the tree is untouched and reads recompute on demand.
    public mutating func invalidateSnapshotCaches() {
        rope.invalidateSnapshotCaches()
    }

    /// Document byte count, O(1). Useful when a caller needs to know retained
    /// document size without materialising any line strings.
    public var byteCount: Int {
        rope.byteCount
    }

    /// A persistent snapshot that can be read off the main actor without materializing every line.
    public var ropeSnapshot: Rope { rope }

    /// Test-only probe — see ``Rope/_testSnapshotCachesAreEmpty``.
    var _testSnapshotCachesAreEmpty: Bool {
        rope._testSnapshotCachesAreEmpty
    }
}

// MARK: - DocumentSource

extension TextBuffer: DocumentSource {
    public func lines(in range: Range<Int>) -> [String] {
        rope.lines(in: range)
    }

    /// The rope stores one `\n` per line break, so the serialized size is its byte count plus what a longer line
    /// ending adds per break: O(1).
    public func serializedByteCount(lineEndingSize: Int) -> Int {
        byteCount + max(0, lineCount - 1) * (lineEndingSize - 1)
    }

    public func maxLineWidth(in range: Range<Int>, tabSize: Int) -> Int {
        let clamped = range.clamped(to: 0 ..< lineCount)
        var maxWidth = 0
        for start in stride(from: clamped.lowerBound, to: clamped.upperBound, by: 4_096) {
            for line in rope.lines(in: start ..< min(start + 4_096, clamped.upperBound)) {
                maxWidth = max(maxWidth, TextDisplayMetrics.displayWidth(of: line, tabSize: tabSize))
            }
        }
        return maxWidth
    }
}

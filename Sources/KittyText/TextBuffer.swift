import Foundation

/// Line-indexed text buffer used by the editor.
///
/// Internally backed by a UTF-8 byte ``Rope`` so insertions and deletions —
/// whether single-character or multi-line bulk replacements — cost O(log n)
/// regardless of where they occur in the document. Line metadata is cached in
/// the rope's tree, so line lookups are also O(log n).
///
/// The public API stays line-oriented for backward compatibility with the
/// many call sites that index by `(row, col)`.
public struct TextBuffer: Sendable {
    private var rope: Rope

    public var lineCount: Int { rope.lineCount }

    /// Materializes every line as a `[String]`. O(n) — prefer the indexed
    /// accessors when you only need a subset.
    public var lines: [String] {
        get {
            var result: [String] = []
            result.reserveCapacity(rope.lineCount)
            for index in 0..<rope.lineCount {
                result.append(rope.line(at: index))
            }
            return result
        }
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
        guard index >= 0, index < lineCount else { return }
        let range = rope.lineRange(forLine: index)
        rope.replace(range, with: value)
    }

    /// Inserts `line` as a new line at logical position `index`.
    ///
    /// `index == lineCount` appends. Insertion is O(log n).
    public mutating func insertLine(_ line: String, at index: Int) {
        let count = lineCount
        guard index >= 0, index <= count else { return }
        if index == count {
            // Append a new last line: add "\n<line>" at the end.
            rope.insert("\n" + line, atByteOffset: rope.byteCount)
        } else {
            // Insert "<line>\n" at the start of line `index`.
            let offset = rope.byteOffset(forLine: index)
            rope.insert(line + "\n", atByteOffset: offset)
        }
    }

    /// Removes the line at `index`, returning its previous content.
    @discardableResult
    public mutating func removeLine(at index: Int) -> String {
        guard index >= 0, index < lineCount else { return "" }
        let removed = rope.line(at: index)
        let count = lineCount

        if count == 1 {
            // Removing the only line: clear content but keep the empty-line invariant.
            rope = Rope("")
            return removed
        }

        if index == count - 1 {
            // Last line: drop the preceding newline + this line's bytes.
            let lineStart = rope.byteOffset(forLine: index)
            rope.remove((lineStart - 1)..<rope.byteCount)
        } else {
            // Drop this line + its terminating newline.
            let lineStart = rope.byteOffset(forLine: index)
            let nextStart = rope.byteOffset(forLine: index + 1)
            rope.remove(lineStart..<nextStart)
        }
        return removed
    }

    /// Reconstructs the full text by joining lines with newlines.
    public var text: String {
        rope.text
    }
}

// MARK: - DocumentSource

extension TextBuffer: DocumentSource {
    public func lines(in range: Range<Int>) -> [String] {
        let clamped = range.clamped(to: 0..<lineCount)
        var result = [String]()
        result.reserveCapacity(clamped.count)
        for lineIndex in clamped {
            result.append(line(at: lineIndex))
        }
        return result
    }

    public func serializedByteCount(lineEndingSize: Int) -> Int {
        var total = 0
        for lineIndex in 0..<lineCount {
            total += line(at: lineIndex).lengthOfBytes(using: .utf8)
        }
        return total + max(0, lineCount - 1) * lineEndingSize
    }

    public func maxLineWidth(in range: Range<Int>, tabSize: Int) -> Int {
        let clamped = range.clamped(to: 0..<lineCount)
        var maxWidth = 0
        for lineIndex in clamped {
            maxWidth = max(
                maxWidth, TextDisplayMetrics.displayWidth(of: line(at: lineIndex), tabSize: tabSize))
        }
        return maxWidth
    }
}

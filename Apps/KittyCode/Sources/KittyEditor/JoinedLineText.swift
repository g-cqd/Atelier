import AtelierText

/// A document that reads the text of a run of lines in one pass, as the lines joined by `\n`, rather than as one
/// string per line that a highlighter joins again.
protocol JoinedLineText: DocumentSource {
    /// The lines `range`, clamped to the document, joined by `\n`: equal to `lines(in: range)` joined by `\n`.
    /// - Complexity: O(log n + bytes of the lines).
    func joinedText(ofLines range: Range<Int>) -> String
}

extension TextBuffer: JoinedLineText {
    /// One ranged read of the rope's bytes, decoded once. A rope keeps one `\n` per line break, so the bytes from the
    /// first line's start to the last line's end are the lines joined by `\n`; `\n` ends any invalid UTF-8 sequence,
    /// so decoding them together repairs them as decoding each line does.
    func joinedText(ofLines range: Range<Int>) -> String {
        let rope = ropeSnapshot
        let clamped = range.clamped(to: 0 ..< rope.lineCount)
        guard !clamped.isEmpty else { return "" }
        let start = rope.lineRange(forLine: clamped.lowerBound).lowerBound
        let end = rope.lineRange(forLine: clamped.upperBound - 1).upperBound
        return String(decoding: rope.bytes(in: start ..< end), as: UTF8.self)
    }
}

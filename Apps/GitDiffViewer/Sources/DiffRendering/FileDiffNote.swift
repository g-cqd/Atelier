/// A difference between a file's two sides that its lines do not show: the diff compares lines without their breaks,
/// and a file's text holds neither its mode nor every byte of its encoding.
package enum FileDiffNote: Equatable, Sendable {
    /// How a side breaks its lines.
    package enum LineEnding: Equatable, Sendable {
        case lf
        case crlf
        case cr
        case mixed

        var name: String {
            switch self {
                case .lf: "LF"
                case .crlf: "CRLF"
                case .cr: "CR"
                case .mixed: "mixed"
            }
        }
    }

    case lineEndings(old: LineEnding, new: LineEnding)
    /// Whether each side ends with a line break.
    case finalNewline(old: Bool, new: Bool)
    case mode(old: String, new: String)
    /// The sides differ, yet read as the same text: a byte-order mark, an encoding, or a byte the text cannot show.
    case unshownBytes

    /// The note as a card header and the status bar show it.
    package var text: String {
        switch self {
            case .lineEndings(let old, let new):
                "Line endings \(old.name) → \(new.name)"
            case .finalNewline(let old, _):
                old ? "No newline at end of file" : "Newline added at end of file"
            case .mode(let old, let new):
                "Mode \(old) → \(new)"
            case .unshownBytes:
                "Only bytes the text does not show differ, such as a byte-order mark or an encoding"
        }
    }

    /// The notes of a file shown on both sides, in a fixed order.
    /// - Parameters:
    ///   - oldText: The old side's text; nil when the file does not exist there.
    ///   - newText: The new side's text; nil when the file does not exist there.
    ///   - oldMode: The mode the old side records, nil when its source records none.
    ///   - newMode: The mode the new side records, nil when its source records none.
    ///   - differs: Whether the sides' contents differ, by their blob ids.
    /// - Returns: No note for a file on one side only.
    package static func notes(
        oldText: String?,
        newText: String?,
        oldMode: String?,
        newMode: String?,
        differs: Bool
    ) -> [FileDiffNote] {
        guard let oldText, let newText else { return [] }
        var notes: [FileDiffNote] = []
        if let oldMode, let newMode, oldMode != newMode { notes.append(.mode(old: oldMode, new: newMode)) }
        if let old = lineEnding(of: oldText), let new = lineEnding(of: newText), old != new {
            notes.append(.lineEndings(old: old, new: new))
        }
        let oldEnds = endsWithBreak(oldText)
        let newEnds = endsWithBreak(newText)
        if !oldText.isEmpty, !newText.isEmpty, oldEnds != newEnds {
            notes.append(.finalNewline(old: oldEnds, new: newEnds))
        }
        if differs, notes.isEmpty, oldText == newText { notes.append(.unshownBytes) }
        return notes
    }

    /// How `text` breaks its lines; nil when it has no line break.
    static func lineEnding(of text: String) -> LineEnding? {
        var found: Set<LineEnding> = []
        var previousWasCR = false
        for byte in text.utf8 {
            if byte == UInt8(ascii: "\n") {
                found.insert(previousWasCR ? .crlf : .lf)
                previousWasCR = false
                continue
            }
            if previousWasCR { found.insert(.cr) }
            previousWasCR = byte == UInt8(ascii: "\r")
            if found.count > 1 { return .mixed }
        }
        if previousWasCR { found.insert(.cr) }
        return found.count > 1 ? .mixed : found.first
    }

    private static func endsWithBreak(_ text: String) -> Bool {
        let last = text.utf8.last
        return last == UInt8(ascii: "\n") || last == UInt8(ascii: "\r")
    }
}

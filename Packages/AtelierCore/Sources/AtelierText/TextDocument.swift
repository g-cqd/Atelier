public import Foundation

/// An open file: its text buffer and cursor, path, language, line ending and dirty state, with cached derivations.
///
/// A class because its owners (`BufferManager`, `WorkspaceSession`) rely on its identity to restore the active
/// buffer's view. It holds no UI state and is not isolated; its `@MainActor` owners keep it on one actor.
public final class TextDocument {
    public enum LineEnding: String, Sendable, Equatable {
        case lineFeed = "lf"
        case carriageReturnLineFeed = "crlf"
        case carriageReturn = "cr"

        public var label: String {
            switch self {
                case .lineFeed:
                    "LF"
                case .carriageReturnLineFeed:
                    "CRLF"
                case .carriageReturn:
                    "CR"
            }
        }

        public var sequence: String {
            switch self {
                case .lineFeed:
                    "\n"
                case .carriageReturnLineFeed:
                    "\r\n"
                case .carriageReturn:
                    "\r"
            }
        }
    }

    public var textBuffer: TextBuffer {
        didSet { invalidateTextSnapshotCache() }
    }
    public var textCursor: TextCursor

    public var cachedFileLines: [String]?
    public var cachedDocumentText: String?
    public var cachedMaxLineWidth: Int?
    public var cachedSerializedByteCount: Int?

    public var filePath: String
    public var fileName: String
    public var language: String?
    public var lineEnding: LineEnding {
        didSet {
            cachedSerializedByteCount = nil
        }
    }

    public var isDirty: Bool = false
    public var isPreview: Bool = false
    public var lastModifiedDate: Date?
    public var externallyModified: Bool = false
    public var documentVersion: Int = 0

    public init(
        filePath: String,
        fileName: String,
        content: String,
        language: String?,
        lineEnding: LineEnding = .lineFeed
    ) {
        self.textBuffer = TextBuffer(content)
        self.textCursor = TextCursor()
        self.filePath = filePath
        self.fileName = fileName
        self.language = language
        self.lineEnding = lineEnding
        self.cachedFileLines = nil
        self.cachedDocumentText = nil
        self.cachedMaxLineWidth = nil
        self.cachedSerializedByteCount = nil
    }

    public var fileContent: [String] {
        get {
            if let cachedFileLines {
                return cachedFileLines
            }

            let lines = textBuffer.lines
            cachedFileLines = lines
            return lines
        }
        set {
            let normalizedLines = newValue.isEmpty ? [""] : newValue
            textBuffer = TextBuffer(lines: normalizedLines)
            cachedFileLines = normalizedLines
            cachedDocumentText = normalizedLines.joined(separator: "\n")
            cachedMaxLineWidth = Self.computeMaxLineWidth(for: normalizedLines)
            cachedSerializedByteCount = Self.computeSerializedByteCount(
                for: normalizedLines, lineEnding: lineEnding)
        }
    }

    public var documentText: String {
        if let cachedDocumentText {
            return cachedDocumentText
        }

        let text = textBuffer.text
        cachedDocumentText = text
        return text
    }

    public var fileLineCount: Int {
        textBuffer.lineCount
    }

    public var isEmpty: Bool {
        textBuffer.isEmpty
    }

    public func line(at index: Int) -> String {
        textBuffer.line(at: index)
    }

    public func replaceDocumentText(with content: String) {
        textBuffer = TextBuffer(content)
        cachedDocumentText = content
        cachedMaxLineWidth = nil
        cachedSerializedByteCount = Self.computeSerializedByteCount(in: textBuffer, lineEnding: lineEnding)
    }

    public func invalidateTextSnapshotCache() {
        cachedFileLines = nil
        cachedDocumentText = nil
        cachedMaxLineWidth = nil
        cachedSerializedByteCount = nil
    }

    public var serializedByteCount: Int {
        if let cachedSerializedByteCount {
            return cachedSerializedByteCount
        }

        let count = Self.computeSerializedByteCount(in: textBuffer, lineEnding: lineEnding)
        cachedSerializedByteCount = count
        return count
    }

    public func serializedText() -> String {
        Self.serializedText(from: documentText, lineEnding: lineEnding)
    }

    nonisolated public static func computeMaxLineWidth<C: Collection>(
        for lines: C, tabSize: Int = 4
    ) -> Int where C.Element == String {
        lines.reduce(0) { max($0, TextDisplayMetrics.displayWidth(of: $1, tabSize: tabSize)) }
    }

    nonisolated public static func computeMaxLineWidth(in buffer: TextBuffer, tabSize: Int = 4)
        -> Int
    {
        buffer.maxLineWidth(in: 0 ..< buffer.lineCount, tabSize: tabSize)
    }

    nonisolated public static func computeSerializedByteCount<C: Collection>(
        for lines: C,
        lineEnding: LineEnding
    ) -> Int where C.Element == String {
        let separatorBytes = lineEnding.sequence.lengthOfBytes(using: .utf8)
        let lineBytes = lines.reduce(0) { partial, line in
            partial + line.lengthOfBytes(using: .utf8)
        }
        return lineBytes + max(0, lines.count - 1) * separatorBytes
    }

    nonisolated public static func computeSerializedByteCount(
        in buffer: TextBuffer,
        lineEnding: LineEnding
    ) -> Int {
        buffer.serializedByteCount(lineEndingSize: lineEnding.sequence.lengthOfBytes(using: .utf8))
    }

    /// `text` with every line break, whichever of LF, CRLF or a lone CR it is, written as `lineEnding`. Idempotent:
    /// serializing serialized text changes nothing, so saving a CRLF file never adds a CR.
    /// - Complexity: O(n) in the UTF-8 length of `text`.
    nonisolated public static func serializedText(from text: String, lineEnding: LineEnding)
        -> String
    {
        replacingLineBreaks(in: text, with: lineEnding)
    }

    /// `text` with every CRLF and every lone CR turned into LF, the one line break a ``TextBuffer`` holds, as a file's
    /// text is loaded.
    /// - Complexity: O(n) in the UTF-8 length of `text`; a text with no CR comes back as is.
    nonisolated public static func normalizingLineBreaks(_ text: String) -> String {
        replacingLineBreaks(in: text, with: .lineFeed)
    }

    /// `text` with each line break, a CRLF pair, a lone CR or a lone LF, replaced by `lineEnding`'s sequence.
    private nonisolated static func replacingLineBreaks(in text: String, with lineEnding: LineEnding) -> String {
        let carriageReturn = UInt8(ascii: "\r")
        let lineFeed = UInt8(ascii: "\n")
        let utf8 = text.utf8
        if lineEnding == .lineFeed, !utf8.contains(carriageReturn) {
            return text
        }
        let separator = Array(lineEnding.sequence.utf8)
        var bytes: [UInt8] = []
        bytes.reserveCapacity(utf8.count)
        var followsCarriageReturn = false
        for byte in utf8 {
            switch byte {
                case carriageReturn:
                    bytes.append(contentsOf: separator)
                    followsCarriageReturn = true
                case lineFeed where followsCarriageReturn:
                    // The CR of this CRLF pair already wrote the separator.
                    followsCarriageReturn = false
                case lineFeed:
                    bytes.append(contentsOf: separator)
                default:
                    followsCarriageReturn = false
                    bytes.append(byte)
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    nonisolated public static func detectLineEnding(in data: Data) -> LineEnding {
        var lfCount = 0
        var crlfCount = 0
        var crCount = 0

        data.withUnsafeBytes { rawBuffer in
            let bytes = rawBuffer.bindMemory(to: UInt8.self)
            var index = 0

            while index < bytes.count {
                switch bytes[index] {
                    case 0x0D:
                        if index + 1 < bytes.count, bytes[index + 1] == 0x0A {
                            crlfCount += 1
                            index += 2
                        } else {
                            crCount += 1
                            index += 1
                        }
                    case 0x0A:
                        lfCount += 1
                        index += 1
                    default:
                        index += 1
                }
            }
        }

        if crlfCount >= lfCount, crlfCount >= crCount, crlfCount > 0 {
            return .carriageReturnLineFeed
        }
        if lfCount >= crCount, lfCount > 0 {
            return .lineFeed
        }
        if crCount > 0 {
            return .carriageReturn
        }
        return .lineFeed
    }
}

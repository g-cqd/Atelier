public import Foundation

/// `TextDocument` was previously `@MainActor` even though it holds only
/// data (`TextBuffer`, `TextCursor`, cached lines, file path, line
/// ending) — no UI-bound state. The isolation propagated transitively
/// into every test that constructed a `DocumentBuffer`, forcing tests
/// onto the main actor with no functional benefit. Audit B3 / NF32.
///
/// The class stays a reference type because consumers (`BufferManager`,
/// `WorkspaceSession`) rely on identity semantics for the active-buffer
/// view-restore handshake. Owners are `@MainActor` (`WorkspaceSession`,
/// `BufferManager`) so the document doesn't cross actor boundaries in
/// practice — isolation is enforced at the owner, not at the document.
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

    public var textBuffer: TextBuffer
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
        let lines = TextBuffer.splitLines(from: content)
        self.textBuffer = TextBuffer(lines: lines)
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
        let lines = TextBuffer.splitLines(from: content)
        textBuffer = TextBuffer(lines: lines)
        cachedFileLines = lines
        cachedDocumentText = content
        cachedMaxLineWidth = Self.computeMaxLineWidth(for: lines)
        cachedSerializedByteCount = Self.computeSerializedByteCount(
            for: lines, lineEnding: lineEnding)
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
        -> Int {
        computeMaxLineWidth(for: buffer.lines, tabSize: tabSize)
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
        var total = 0
        let separatorBytes = lineEnding.sequence.lengthOfBytes(using: .utf8)

        for lineIndex in 0..<buffer.lineCount {
            total += buffer.line(at: lineIndex).lengthOfBytes(using: .utf8)
        }

        return total + max(0, buffer.lineCount - 1) * separatorBytes
    }

    nonisolated public static func serializedText(from text: String, lineEnding: LineEnding)
        -> String {
        guard lineEnding != .lineFeed else { return text }
        return text.replacingOccurrences(of: "\n", with: lineEnding.sequence)
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

import Foundation
import KittyGit
import KittySyntax
import KittyText

@MainActor
final class DocumentBuffer {
    var textBuffer: TextBuffer
    var textCursor: TextCursor
    var highlightedLines: [[StyledSpan]]
    var highlightSession: LanguageHighlighter.Session?
    var cachedFileLines: [String]?
    var cachedDocumentText: String?

    var filePath: String
    var fileName: String
    var language: String?

    var isDirty: Bool = false
    var isPreview: Bool = false
    var lastModifiedDate: Date?
    var externallyModified: Bool = false
    var highlightGeneration: Int = 0
    var documentVersion: Int = 0
    var gitLineDecorations: GitLineDecorations = .empty

    init(
        filePath: String,
        fileName: String,
        content: String,
        language: String?
    ) {
        let lines = TextBuffer.splitLines(from: content)
        self.filePath = filePath
        self.fileName = fileName
        self.language = language
        self.textBuffer = TextBuffer(lines: lines)
        self.textCursor = TextCursor()
        self.highlightedLines = [[StyledSpan(text: "", style: .default)]]
        self.cachedFileLines = lines
        self.cachedDocumentText = content
    }
}

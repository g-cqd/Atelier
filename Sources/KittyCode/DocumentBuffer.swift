import Foundation
import KittyGit
import KittySyntax
import KittyText

@MainActor
final class DocumentBuffer {
    let document: TextDocument
    var highlightedLines: [[StyledSpan]]
    var highlightSession: LanguageHighlighter.Session?
    var highlightGeneration: Int = 0
    var gitLineDecorations: GitLineDecorations = .empty
    var postOpenProcessingTask: Task<Void, Never>?

    var textBuffer: TextBuffer {
        get { document.textBuffer }
        set { document.textBuffer = newValue }
    }

    var textCursor: TextCursor {
        get { document.textCursor }
        set { document.textCursor = newValue }
    }

    var cachedFileLines: [String]? {
        get { document.cachedFileLines }
        set { document.cachedFileLines = newValue }
    }

    var cachedDocumentText: String? {
        get { document.cachedDocumentText }
        set { document.cachedDocumentText = newValue }
    }

    var cachedMaxLineWidth: Int? {
        get { document.cachedMaxLineWidth }
        set { document.cachedMaxLineWidth = newValue }
    }

    var cachedSerializedByteCount: Int? {
        get { document.cachedSerializedByteCount }
        set { document.cachedSerializedByteCount = newValue }
    }

    var filePath: String {
        get { document.filePath }
        set { document.filePath = newValue }
    }

    var fileName: String {
        get { document.fileName }
        set { document.fileName = newValue }
    }

    var language: String? {
        get { document.language }
        set { document.language = newValue }
    }

    var lineEnding: TextDocument.LineEnding {
        get { document.lineEnding }
        set { document.lineEnding = newValue }
    }

    var serializedByteCount: Int {
        document.serializedByteCount
    }

    var isDirty: Bool {
        get { document.isDirty }
        set { document.isDirty = newValue }
    }

    var isPreview: Bool {
        get { document.isPreview }
        set { document.isPreview = newValue }
    }

    var lastModifiedDate: Date? {
        get { document.lastModifiedDate }
        set { document.lastModifiedDate = newValue }
    }

    var externallyModified: Bool {
        get { document.externallyModified }
        set { document.externallyModified = newValue }
    }

    var documentVersion: Int {
        get { document.documentVersion }
        set { document.documentVersion = newValue }
    }

    init(
        filePath: String,
        fileName: String,
        content: String,
        language: String?,
        lineEnding: TextDocument.LineEnding = .lf
    ) {
        self.document = TextDocument(
            filePath: filePath,
            fileName: fileName,
            content: content,
            language: language,
            lineEnding: lineEnding
        )
        self.highlightedLines = [[StyledSpan(text: "", style: .default)]]
    }

    deinit {
        postOpenProcessingTask?.cancel()
    }
}

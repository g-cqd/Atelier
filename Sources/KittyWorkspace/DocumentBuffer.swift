import Foundation
import KittyGit
import KittySyntax
import KittyText

@MainActor
public final class DocumentBuffer {
    public let document: TextDocument
    public let editHistory: BufferEditHistory
    public var highlightedLines: [[StyledSpan]]
    public var highlightSession: LanguageHighlighter.Session?
    public var highlightGeneration: Int = 0
    public var gitLineDecorations: GitLineDecorations = .empty
    public var postOpenProcessingTask: Task<Void, Never>?
    public var didInvalidateHistoryOnLastRefresh: Bool = false
    public var selection: TextSelection?

    public var textBuffer: TextBuffer {
        get { document.textBuffer }
        set { document.textBuffer = newValue }
    }

    public var textCursor: TextCursor {
        get { document.textCursor }
        set { document.textCursor = newValue }
    }

    /// Drops the heavy materialised caches a buffer accumulates while
    /// active: full-document text string, `[String]` line array, the
    /// per-line styled-span highlight array, and the per-buffer
    /// highlight session. Audit B.8/F12 — called when this buffer
    /// becomes inactive (tab switch). Without it a 5-buffer session
    /// with each buffer at ~1 MB pinned ~12–20 MB of redundant
    /// highlight + cache data per inactive tab. On next activation the
    /// caches rehydrate lazily.
    ///
    /// The document's `textBuffer` (the rope), `textCursor`,
    /// `editHistory`, `gitLineDecorations`, and `selection` are
    /// preserved — these are the user-visible state that distinguishes
    /// one tab from another. Only the derived caches drop.
    public func evictInactiveCaches() {
        document.cachedFileLines = nil
        document.cachedDocumentText = nil
        document.cachedSerializedByteCount = nil
        document.cachedMaxLineWidth = nil
        highlightedLines = [[StyledSpan(text: "", style: .default)]]
        highlightSession = nil
    }

    // Cache forwarders — `package` access matches the underlying `TextDocument`
    // fields. External callers should use `invalidateTextSnapshotCache()` and
    // friends; these direct setters are only for `EditorState`'s forwarding
    // layer in `KittyCode`. Audit B2.
    package var cachedFileLines: [String]? {
        get { document.cachedFileLines }
        set { document.cachedFileLines = newValue }
    }

    package var cachedDocumentText: String? {
        get { document.cachedDocumentText }
        set { document.cachedDocumentText = newValue }
    }

    package var cachedMaxLineWidth: Int? {
        get { document.cachedMaxLineWidth }
        set { document.cachedMaxLineWidth = newValue }
    }

    package var cachedSerializedByteCount: Int? {
        get { document.cachedSerializedByteCount }
        set { document.cachedSerializedByteCount = newValue }
    }

    public var filePath: String {
        get { document.filePath }
        set { document.filePath = newValue }
    }

    public var fileName: String {
        get { document.fileName }
        set { document.fileName = newValue }
    }

    public var language: String? {
        get { document.language }
        set { document.language = newValue }
    }

    public var lineEnding: TextDocument.LineEnding {
        get { document.lineEnding }
        set { document.lineEnding = newValue }
    }

    public var serializedByteCount: Int {
        document.serializedByteCount
    }

    public var isDirty: Bool {
        get { document.isDirty }
        set { document.isDirty = newValue }
    }

    public var isPreview: Bool {
        get { document.isPreview }
        set { document.isPreview = newValue }
    }

    public var lastModifiedDate: Date? {
        get { document.lastModifiedDate }
        set { document.lastModifiedDate = newValue }
    }

    public var externallyModified: Bool {
        get { document.externallyModified }
        set { document.externallyModified = newValue }
    }

    public var documentVersion: Int {
        get { document.documentVersion }
        set { document.documentVersion = newValue }
    }

    public init(
        filePath: String,
        fileName: String,
        content: String,
        language: String?,
        lineEnding: TextDocument.LineEnding = .lineFeed,
        maxUndoSteps: Int = 200
    ) {
        self.document = TextDocument(
            filePath: filePath,
            fileName: fileName,
            content: content,
            language: language,
            lineEnding: lineEnding
        )
        self.editHistory = BufferEditHistory(
            initial: BufferEditSnapshot(
                textBuffer: document.textBuffer,
                textCursor: document.textCursor,
                lineEnding: document.lineEnding
            )
        )
        self.editHistory.maxUndoSteps = maxUndoSteps
        self.highlightedLines = [[StyledSpan(text: "", style: .default)]]
    }

    deinit {
        postOpenProcessingTask?.cancel()
    }
}

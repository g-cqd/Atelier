public import AemiCore
public import AtelierText
public import Foundation
import KittyFileTree
public import KittyGit
import KittyStyle
public import KittySyntax

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

    /// Drops what an inactive tab can rebuild lazily: the text, line, size and width caches, the highlighted lines
    /// and the highlight session. The rope, cursor, history, selection and git marks stay.
    public func evictInactiveCaches() {
        document.cachedFileLines = nil
        document.cachedDocumentText = nil
        document.cachedSerializedByteCount = nil
        document.cachedMaxLineWidth = nil
        highlightedLines = [[StyledSpan(text: "", style: .default)]]
        highlightSession = nil
    }

    // Cache forwarders for `EditorState`'s forwarding layer; everything else invalidates through
    // `invalidateTextSnapshotCache()`.
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

    /// Whether an autosave is writing this buffer's file in the background. A save or reload of the buffer waits for
    /// it, and a watcher event for the file sets ``hasDiskCheckPending`` instead of acting.
    public var isSavingInBackground = false
    /// Whether the file may have changed while ``isSavingInBackground`` held, so it is to be checked once the save
    /// lands.
    public var hasDiskCheckPending = false

    /// Whether saving over ``filePath`` would overwrite a change made outside the editor: the watcher flagged one, or
    /// the file's modification date differs from the one this buffer last read or wrote. A missing file conflicts
    /// with nothing, and a buffer that never read or wrote its file has no date to compare.
    public func conflictsWithDisk() -> Bool {
        if externallyModified { return true }
        guard let lastModifiedDate, let diskDate = WorkspaceFileLoading.modificationDate(ofFileAt: filePath) else {
            return false
        }
        return diskDate != lastModifiedDate
    }

    /// Whether `path` names this buffer's file, symlinks and `/private` spellings resolved; never for a buffer with no
    /// file yet.
    public func isFile(at path: String) -> Bool {
        guard !filePath.isEmpty else { return false }
        return filePath == path
            || !Set(FileWatcher.canonicalPaths(forFile: filePath))
                .isDisjoint(with: FileWatcher.canonicalPaths(forFile: path))
    }

    /// Reads this buffer's file and makes it the text as one undo step, so undo brings back what it replaced, unsaved
    /// against the file. A buffer that changes or starts saving while the file is read keeps its newer text.
    /// - Parameters:
    ///   - taskProvider: Runs the blocking read.
    ///   - syncLiveState: Runs just before the text is replaced: an active buffer copies its live text and cursor in.
    /// - Returns: The file's text, or nil when the buffer kept its newer text.
    /// - Throws: The read's error.
    public func reloadFromDisk(taskProvider: any TaskProvider, syncLiveState: () -> Void) async throws -> LoadedFile? {
        let path = filePath
        let version = documentVersion
        // Read before the text, as an open does, so a change landing between the two reads as newer.
        let date = WorkspaceFileLoading.modificationDate(ofFileAt: path)
        let file = try await WorkspaceFileLoading.readUTF8File(at: path, taskProvider: taskProvider)
        guard documentVersion == version, filePath == path, !isSavingInBackground else { return nil }
        syncLiveState()
        let replaced = BufferEditSnapshot(
            textBuffer: textBuffer, textCursor: textCursor, lineEnding: lineEnding, selection: selection)
        replaceContents(with: file, modifiedAt: date)
        let reloaded = BufferEditSnapshot(textBuffer: textBuffer, textCursor: textCursor, lineEnding: lineEnding)
        editHistory.recordChange(from: replaced, to: reloaded, coalescingWindow: nil)
        editHistory.markSaved(reloaded)
        isDirty = false
        didInvalidateHistoryOnLastRefresh = false
        return file
    }

    /// Replaces the text with `file`'s, as a reload from disk does: the caches, highlights and selection go, the
    /// cursor is clamped into the new text, and the buffer is no longer externally modified. The edit history is the
    /// caller's to update.
    /// - Parameters:
    ///   - file: The text and line ending read from disk.
    ///   - date: The file's modification date when it was read.
    public func replaceContents(with file: LoadedFile, modifiedAt date: Date?) {
        postOpenProcessingTask?.cancel()
        postOpenProcessingTask = nil
        textBuffer = TextBuffer(file.content)
        lineEnding = file.lineEnding
        lastModifiedDate = date
        externallyModified = false
        selection = nil
        highlightedLines = []
        highlightSession = nil
        document.invalidateTextSnapshotCache()
        documentVersion += 1

        let lineCount = textBuffer.lineCount
        textCursor.row = min(textCursor.row, max(0, lineCount - 1))
        textCursor.col = min(textCursor.col, textBuffer.line(at: textCursor.row).count)
        textCursor.scrollRow = min(textCursor.scrollRow, max(0, lineCount - 1))
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

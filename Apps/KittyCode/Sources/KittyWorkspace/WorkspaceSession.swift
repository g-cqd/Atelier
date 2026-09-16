import Foundation
import KittyGit
import KittyStyle
public import KittySyntax
public import KittyText

@MainActor
public final class WorkspaceSession: ActiveDocumentView, WorkspaceCommands {
    public var rootPath: String
    public let bufferManager = BufferManager()
    public let treeState: WorkspaceTreeState

    // MARK: - Active document state

    public var textBuffer = TextBuffer()
    public var textCursor = TextCursor()
    public var fileName: String = ""
    public var filePath: String = ""
    public var currentLanguage: String?
    public var currentLineEnding: TextDocument.LineEnding = .lineFeed
    public var highlightSession: LanguageHighlighter.Session?
    public var highlightedLines: [[StyledSpan]] = [[StyledSpan(text: "", style: .default)]]

    // MARK: - Document caches
    //
    // Implementation detail of the cache invalidation contract — exposed
    // at `package` access so `EditorState`'s forwarding setters in
    // `KittyCode` can clear them in the right order (always together via
    // `invalidateTextSnapshotCache()`, except for `cachedMaxLineWidth`
    // which is rebuilt incrementally via `widenCachedMaxLineWidth`). No
    // external package should write these; the public methods on
    // `WorkspaceSession` are the supported surface. Audit B2.

    package var cachedFileLines: [String]?
    package var cachedDocumentText: String?
    package var cachedSerializedByteCount: Int?
    package var cachedMaxLineWidth: Int?

    // MARK: - File open tracking

    private var fileOpenTask: Task<Void, Never>?
    private var pendingOpenRequestID: UInt64 = 0

    // MARK: - Callbacks

    public var onTabSwitched: (() -> Void)?

    public init(rootPath: String) {
        self.rootPath = rootPath
        self.treeState = WorkspaceTreeState(rootPath: rootPath)
    }

    // MARK: - Active buffer synchronization

    public func saveStateToActiveBuffer() {
        guard let buf = bufferManager.activeBuffer else { return }
        buf.textBuffer = textBuffer
        buf.textCursor = textCursor
        buf.highlightedLines = highlightedLines
        buf.highlightSession = highlightSession
        buf.cachedFileLines = cachedFileLines
        buf.cachedDocumentText = cachedDocumentText
        buf.cachedMaxLineWidth = cachedMaxLineWidth
        buf.cachedSerializedByteCount = cachedSerializedByteCount
        buf.language = currentLanguage
        buf.lineEnding = currentLineEnding
    }

    public func restoreStateFromActiveBuffer() {
        guard let buf = bufferManager.activeBuffer else { return }
        textBuffer = buf.textBuffer
        textCursor = buf.textCursor
        highlightedLines = buf.highlightedLines
        highlightSession = buf.highlightSession
        currentLanguage = buf.language
        fileName = buf.fileName
        filePath = buf.filePath
        cachedFileLines = buf.cachedFileLines
        cachedDocumentText = buf.cachedDocumentText
        cachedMaxLineWidth = buf.cachedMaxLineWidth
        cachedSerializedByteCount = buf.cachedSerializedByteCount
        currentLineEnding = buf.lineEnding
    }

    public func switchToTab(_ index: Int) {
        guard index != bufferManager.activeIndex, index >= 0, index < bufferManager.count else {
            return
        }
        saveStateToActiveBuffer()
        // Audit B.8/F12 — drop the now-inactive buffer's
        // text/lines/highlight caches before switching. With ~5
        // buffers each at 1 MB, this caps inactive-buffer cache
        // residency at ~0 (just the rope itself, which is the
        // user-visible state) instead of ~12-20 MB per tab.
        if let outgoing = bufferManager.activeBuffer {
            outgoing.evictInactiveCaches()
        }
        bufferManager.switchTo(index: index)
        restoreStateFromActiveBuffer()
        onTabSwitched?()
    }

    // MARK: - Document text access

    public var fileContent: [String] {
        if let cachedFileLines {
            return cachedFileLines
        }
        let lines = textBuffer.lines
        cachedFileLines = lines
        return lines
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

    public var isFileEmpty: Bool {
        textBuffer.isEmpty
    }

    public func fileLine(at index: Int) -> String {
        textBuffer.line(at: index)
    }

    public func highlightedLine(at index: Int) -> [StyledSpan] {
        guard index >= 0 && index < highlightedLines.count else {
            return [StyledSpan(text: "", style: .default)]
        }
        return highlightedLines[index]
    }

    public var serializedByteCount: Int {
        if let cachedSerializedByteCount {
            return cachedSerializedByteCount
        }
        let count = TextDocument.computeSerializedByteCount(
            in: textBuffer, lineEnding: currentLineEnding)
        cachedSerializedByteCount = count
        return count
    }

    public var maxLineWidth: Int {
        cachedMaxLineWidth ?? 0
    }

    // MARK: - Cache management

    public func invalidateTextSnapshotCache() {
        cachedFileLines = nil
        cachedDocumentText = nil
        cachedMaxLineWidth = nil
        cachedSerializedByteCount = nil
    }

    public func invalidateHighlightSession() {
        highlightSession = nil
    }

    public func replaceDocumentText(
        with content: String, tabSize: Int, lineEnding: TextDocument.LineEnding
    ) {
        let lines = TextBuffer.splitLines(from: content)
        textBuffer = TextBuffer(lines: lines)
        cachedFileLines = lines
        cachedDocumentText = content
        cachedMaxLineWidth = TextDocument.computeMaxLineWidth(for: lines, tabSize: tabSize)
        cachedSerializedByteCount = TextDocument.computeSerializedByteCount(
            for: lines, lineEnding: lineEnding)
        highlightSession = nil
    }

    // MARK: - File open task management

    public func nextOpenRequestID() -> UInt64 {
        pendingOpenRequestID &+= 1
        return pendingOpenRequestID
    }

    public func replaceFileOpenTask(with task: Task<Void, Never>) {
        fileOpenTask?.cancel()
        fileOpenTask = task
    }

    public func cancelPendingFileOpen() {
        fileOpenTask?.cancel()
        fileOpenTask = nil
    }

    public func isCurrentOpenRequest(_ requestID: UInt64) -> Bool {
        pendingOpenRequestID == requestID
    }

    deinit {
        fileOpenTask?.cancel()
    }
}

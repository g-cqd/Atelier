import AemiTesting
import Foundation
import KittyStyle
import KittyWorkspace
import Synchronization
import Testing

@testable import AtelierText
@testable import KittyEditor
@testable import KittySyntax

/// Closing, switching away from or replacing a tab and reloading a file hand the old document's storage to `retire`,
/// whose consumer frees it off the main actor, and keep no other reference to it, so the consumer's is the last.
@Suite
@MainActor
struct EditorRetiredStorageTests {
    /// What the state handed to `retire`.
    private final class RetiredLog: Sendable {
        let entries = Mutex<[EditorState.RetiredStorage]>([])

        /// Moves the entries out, so that the log holds no reference to what they hold.
        func take() -> [EditorState.RetiredStorage] {
            entries.withLock { entries in
                defer { entries = [] }
                return entries
            }
        }
    }

    private static let lines = (0 ..< 200).map { "let value\($0) = compute(\($0)) // a note long enough for the heap" }

    /// A Swift file open in the only tab, as a preview when `preview`, its highlights shared by the buffer and the
    /// screen as an open leaves them, with `retire` recorded from here on.
    private func makeState(preview: Bool = false) -> (state: EditorState, log: RetiredLog) {
        let state = EditorState(
            rootPath: ".", config: KittyConfig(), taskProvider: TaskProviderSpy(), searchPool: EditorTestPool.shared)
        let content = Self.lines.joined(separator: "\n")
        if preview {
            state.config.tabRibbon.persistence = .preview
            state.bufferManager.openPreview(
                filePath: "/project/file.swift", fileName: "file.swift", content: content, language: "swift")
        } else {
            state.bufferManager.open(
                filePath: "/project/file.swift", fileName: "file.swift", content: content, language: "swift")
        }
        state.workspace.restoreStateFromActiveBuffer()
        state.highlightedLines = LineHighlights(Self.lines.map { [StyledSpan(text: $0, style: .default)] })
        state.saveStateToActiveBuffer()
        let log = RetiredLog()
        state.retire = { storage in log.entries.withLock { $0.append(storage) } }
        return (state, log)
    }

    /// Whether `array` holds the only reference to its storage: mutable access copies shared storage first.
    private func isUniquelyReferenced<Element>(_ array: inout [Element]) -> Bool {
        let shared = array.withUnsafeBufferPointer { $0.baseAddress }
        let owned = array.withUnsafeMutableBufferPointer { UnsafePointer($0.baseAddress) }
        return shared == owned
    }

    /// Expects the closed buffer, then the highlights it shares, to be held by the retired storage alone.
    private func expectOnlyRetiredReferences(
        buffer retiredBuffer: inout DocumentBuffer?, highlights: inout LineHighlights
    ) throws {
        var buffer = try #require(retiredBuffer)
        retiredBuffer = nil
        #expect(isKnownUniquelyReferenced(&buffer))
        // The buffer's own copy of the highlights goes with it.
        buffer.highlightedLines = []
        #expect(isUniquelyReferenced(&highlights.storedLines))
    }

    @Test
    func `closing the last tab retires the document's highlights, text and buffer and keeps none of them`() throws {
        let (state, log) = makeState()
        defer { state.shutdown() }
        let hash = state.textBuffer.contentHash
        let closedID = ObjectIdentifier(try #require(state.bufferManager.activeBuffer))

        state.closeCurrentTab()

        var entries = log.take()
        try #require(entries.count == 1)
        var retired = entries.removeFirst()
        #expect(retired.buffer.map(ObjectIdentifier.init) == closedID)
        #expect(retired.textBuffer?.contentHash == hash)
        var highlights = retired.highlights
        retired.highlights = []
        #expect(highlights == LineHighlights(Self.lines.map { [StyledSpan(text: $0, style: .default)] }))
        try expectOnlyRetiredReferences(buffer: &retired.buffer, highlights: &highlights)
    }

    @Test
    func `closing a tab with another open retires the closed document and keeps none of it`() throws {
        let (state, log) = makeState()
        defer { state.shutdown() }
        state.bufferManager.open(filePath: "/project/other.txt", fileName: "other.txt", content: "other", language: nil)
        state.bufferManager.switchTo(index: 0)
        _ = log.take()

        state.closeCurrentTab()

        #expect(state.fileName == "other.txt")
        var entries = log.take()
        let index = try #require(entries.firstIndex { $0.buffer != nil })
        var retired = entries.remove(at: index)
        var highlights = retired.highlights
        retired.highlights = []
        #expect(highlights.count == Self.lines.count)
        try expectOnlyRetiredReferences(buffer: &retired.buffer, highlights: &highlights)
    }

    @Test
    func `reloading the active file retires the old text's highlights and lines and keeps no highlight`() throws {
        let (state, log) = makeState()
        defer { state.shutdown() }
        _ = state.fileContent
        let buffer = try #require(state.bufferManager.activeBuffer)
        let file = LoadedFile(content: "changed on disk\n", lineEnding: .lineFeed)

        // What the file watcher does once its read lands.
        state.saveStateToActiveBuffer()
        let replaced = buffer.replaceContents(with: file, modifiedAt: nil)
        state.fileWatcherDidReloadActiveBuffer(buffer: buffer, content: file.content, replaced: consume replaced)

        #expect(state.textBuffer.text == "changed on disk\n")
        var entries = log.take()
        let index = try #require(entries.firstIndex { $0.highlights.count == Self.lines.count })
        var retired = entries.remove(at: index)
        // The lines are also the old rope's cache, which the reload's undo step keeps.
        #expect(retired.fileLines == Self.lines)
        var highlights = retired.highlights
        retired.highlights = []
        // The buffer's own copy of the highlights, which it let go of, goes with them.
        #expect(retired.replaced?.highlights.count == Self.lines.count)
        retired.replaced = nil
        #expect(isUniquelyReferenced(&highlights.storedLines))
    }

    /// Opens a short file through the open path once its read has finished, as a click in the tree does.
    private func openOtherFile(in state: EditorState) {
        state.saveStateToActiveBuffer()
        state.finishOpeningFile(
            requestID: state.nextOpenRequestID(), path: "/project/other.swift", name: "other.swift",
            loadedFile: LoadedFile(content: "let other = 1\n", lineEnding: .lineFeed), language: "swift",
            modificationDate: nil)
    }

    @Test
    func `switching away from a tab retires its highlights and keeps none of them`() throws {
        let (state, log) = makeState()
        defer { state.shutdown() }
        _ = state.fileContent
        state.bufferManager.open(filePath: "/project/other.txt", fileName: "other.txt", content: "other", language: nil)
        state.bufferManager.switchTo(index: 0)
        _ = log.take()

        state.switchToTab(1)

        #expect(state.fileName == "other.txt")
        var entries = log.take()
        let index = try #require(entries.firstIndex { $0.highlights.count == Self.lines.count })
        var retired = entries.remove(at: index)
        // The lines are also the rope's own cache, which stays with the outgoing buffer.
        #expect(retired.fileLines == Self.lines)
        #expect(retired.textBuffer == nil)
        var highlights = retired.highlights
        retired.highlights = []
        #expect(highlights == LineHighlights(Self.lines.map { [StyledSpan(text: $0, style: .default)] }))
        #expect(isUniquelyReferenced(&highlights.storedLines))
    }

    @Test
    func `opening a file in preview mode retires the active preview it replaces and keeps none of it`() throws {
        let (state, log) = makeState(preview: true)
        defer { state.shutdown() }
        let previewID = ObjectIdentifier(try #require(state.bufferManager.activeBuffer))
        let hash = state.textBuffer.contentHash

        openOtherFile(in: state)

        #expect(state.bufferManager.buffers.map(\.fileName) == ["other.swift"])
        var entries = log.take()
        let index = try #require(entries.firstIndex { $0.buffer != nil })
        var retired = entries.remove(at: index)
        #expect(retired.buffer.map(ObjectIdentifier.init) == previewID)
        #expect(retired.textBuffer?.contentHash == hash)
        var highlights = retired.highlights
        retired.highlights = []
        #expect(highlights.count == Self.lines.count)
        try expectOnlyRetiredReferences(buffer: &retired.buffer, highlights: &highlights)
    }

    @Test
    func `opening a file in preview mode retires an inactive preview it replaces and keeps none of it`() throws {
        let (state, log) = makeState(preview: true)
        defer { state.shutdown() }
        let previewID = ObjectIdentifier(try #require(state.bufferManager.activeBuffer))
        // A pinned tab in front of the preview, which keeps its highlights.
        state.bufferManager.open(filePath: "/project/other.txt", fileName: "other.txt", content: "other", language: nil)
        state.workspace.restoreStateFromActiveBuffer()
        _ = log.take()

        openOtherFile(in: state)

        #expect(state.bufferManager.buffers.map(\.fileName) == ["other.txt", "other.swift"])
        var entries = log.take()
        let index = try #require(entries.firstIndex { $0.buffer != nil })
        var retired = entries.remove(at: index)
        #expect(retired.buffer.map(ObjectIdentifier.init) == previewID)
        // The workspace held the pinned tab, not the preview.
        #expect(retired.textBuffer == nil)
        var highlights = try #require(retired.buffer).highlightedLines
        #expect(highlights.count == Self.lines.count)
        try expectOnlyRetiredReferences(buffer: &retired.buffer, highlights: &highlights)
    }

    @Test
    func `reloading an inactive tab retires its old text's highlights and keeps none of them`() throws {
        let (state, log) = makeState()
        defer { state.shutdown() }
        let buffer = try #require(state.bufferManager.activeBuffer)
        let oldText = state.textBuffer.text
        // An open leaves the tab it leaves with its highlights.
        openOtherFile(in: state)
        #expect(buffer.highlightedLines.count == Self.lines.count)
        _ = log.take()
        let file = LoadedFile(content: "changed on disk\n", lineEnding: .lineFeed)

        // What the file watcher does once its read lands.
        let replaced = buffer.replaceContents(with: file, modifiedAt: nil)
        state.fileWatcherDidReloadInactiveBuffer(buffer: buffer, content: file.content, replaced: consume replaced)

        #expect(buffer.textBuffer.text == "changed on disk\n")
        #expect(state.fileName == "other.swift")
        var entries = log.take()
        try #require(entries.count == 1)
        var retired = try #require(entries.removeFirst().replaced)
        #expect(retired.textBuffer.text == oldText)
        var highlights = retired.highlights
        retired.highlights = []
        #expect(highlights == LineHighlights(Self.lines.map { [StyledSpan(text: $0, style: .default)] }))
        #expect(isUniquelyReferenced(&highlights.storedLines))
    }
}

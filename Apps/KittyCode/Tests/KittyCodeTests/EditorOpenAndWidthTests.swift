import AemiCore
import AemiTesting
import Foundation
import KittySyntax
import Testing

@testable import AtelierText
@testable import KittyEditor
@testable import KittyWorkspace

/// Opening a file installs the rope its read built, and a document's width is measured only off the main actor: by
/// the post-load pass after an open, by the full pass otherwise.
@Suite
@MainActor
struct EditorOpenAndWidthTests {
    private static let widestLine = String(repeating: "w", count: 300)
    private static let lines = (0 ..< 200).map { $0 == 150 ? widestLine : "line \($0)" }
    private static let text = lines.joined(separator: "\n")

    private func makeState() -> (state: EditorState, tasks: TaskProviderSpy) {
        let tasks = TaskProviderSpy(defaultTimeout: .seconds(20))
        return (EditorState(rootPath: ".", config: KittyConfig(), taskProvider: tasks), tasks)
    }

    /// Opens `text` in a new buffer and waits for the full pass its restore asks for, so it starts highlighted and
    /// measured.
    private func open(
        _ text: String = Self.text, path: String = "/project/wide.txt", in state: EditorState, tasks: TaskProviderSpy
    ) async throws {
        state.saveStateToActiveBuffer()
        let spawned = tasks.spawnedTaskCount
        state.bufferManager.open(filePath: path, fileName: "wide.txt", content: text, language: nil)
        state.restoreStateFromActiveBuffer()
        try await awaitFullPass(tasks, after: spawned)
    }

    /// Waits, within the spy's bound, for the next pass to be spawned and for every task to finish.
    private func awaitFullPass(_ tasks: TaskProviderSpy, after spawned: Int) async throws {
        try await tasks.waitForSpawnedTasks(atLeast: spawned + 1)
        try await tasks.waitForAllTasks()
    }

    private func openRead(_ loadedFile: LoadedFile, in state: EditorState) {
        state.finishOpeningFile(
            requestID: state.nextOpenRequestID(), path: "/project/wide.txt", name: "wide.txt",
            loadedFile: loadedFile, language: nil, modificationDate: nil)
    }

    @Test
    func `opening a file installs the rope its read built`() throws {
        let (state, _) = makeState()
        defer { state.shutdown() }
        let loadedFile = try WorkspaceFileLoading.decode(Data(Self.text.utf8))
        // Materialised on the read's rope only: a rope rebuilt from the text on the main actor starts without them.
        _ = loadedFile.textBuffer.lines

        openRead(loadedFile, in: state)

        #expect(!state.textBuffer._testSnapshotCachesAreEmpty)
        #expect(state.fileLine(at: 150) == Self.widestLine)
    }

    @Test
    func `a file being opened is measured off the main actor`() async throws {
        let (state, tasks) = makeState()
        defer { state.shutdown() }

        openRead(try WorkspaceFileLoading.decode(Data(Self.text.utf8)), in: state)

        #expect(state.maxLineWidth == 0)
        #expect(state.cachedMaxLineWidth == nil)
        try await tasks.waitForAllTasks()
        #expect(state.maxLineWidth == Self.widestLine.count)
    }

    @Test
    func `a post-load pass the text outran hands the document to the full pass`() async throws {
        let (state, tasks) = makeState()
        defer { state.shutdown() }
        openRead(try WorkspaceFileLoading.decode(Data(Self.text.utf8)), in: state)
        let buffer = try #require(state.bufferManager.activeBuffer)

        // A new version without cancelling the pass, as replacing across the workspace makes one.
        buffer.documentVersion += 1

        try await awaitFullPass(tasks, after: 1)
        #expect(buffer.postOpenProcessingTask == nil)
        #expect(state.maxLineWidth == Self.widestLine.count)
    }

    @Test
    func `an edit that cancels a pending post-load pass hands its work to the full pass`() async throws {
        let (state, tasks) = makeState()
        defer { state.shutdown() }
        try await open(in: state, tasks: tasks)
        let buffer = try #require(state.bufferManager.activeBuffer)
        buffer.postOpenProcessingTask = tasks.task(role: .work) {}
        state.cachedMaxLineWidth = nil
        let spawned = tasks.spawnedTaskCount

        insertText("x", into: state)

        try await awaitFullPass(tasks, after: spawned)
        #expect(state.maxLineWidth == Self.widestLine.count)
    }

    @Test
    func `undo leaves the width to the full pass`() async throws {
        let (state, tasks) = makeState()
        defer { state.shutdown() }
        try await open(in: state, tasks: tasks)
        insertText("x", into: state)
        let spawned = tasks.spawnedTaskCount

        state.undoActiveBuffer()

        #expect(state.cachedMaxLineWidth == nil)
        try await awaitFullPass(tasks, after: spawned)
        #expect(state.maxLineWidth == Self.widestLine.count)
    }

    @Test
    func `an edit before the width is measured leaves it to the full pass`() async throws {
        let (state, tasks) = makeState()
        defer { state.shutdown() }
        try await open(in: state, tasks: tasks)
        insertText("x", into: state)
        state.undoActiveBuffer()
        let spawned = tasks.spawnedTaskCount
        state.cursorRow = 10

        insertText("y", into: state)

        #expect(state.cachedMaxLineWidth == nil)
        try await awaitFullPass(tasks, after: spawned)
        #expect(state.maxLineWidth == Self.widestLine.count)
    }

    @Test
    func `switching back to a tab evicted while inactive highlights its lines on screen at once`() async throws {
        let (state, tasks) = makeState()
        defer { state.shutdown() }
        try await open(in: state, tasks: tasks)
        try await open("short", path: "/project/short.txt", in: state, tasks: tasks)
        state.switchToTab(0)
        state.switchToTab(1)

        state.switchToTab(0)

        #expect(state.highlightedLines.count == Self.lines.count)
        #expect(state.highlightedLines[0].map(\.text).joined() == Self.lines[0])
    }

    @Test
    func `switching back to a tab evicted while inactive measures it off the main actor`() async throws {
        let (state, tasks) = makeState()
        defer { state.shutdown() }
        try await open(in: state, tasks: tasks)
        try await open("short", path: "/project/short.txt", in: state, tasks: tasks)
        state.switchToTab(0)
        state.switchToTab(1)
        let spawned = tasks.spawnedTaskCount

        state.switchToTab(0)

        #expect(state.maxLineWidth == 0)
        #expect(state.cachedMaxLineWidth == nil)
        try await awaitFullPass(tasks, after: spawned)
        #expect(state.maxLineWidth == Self.widestLine.count)
    }

    @Test
    func `closing a tab refreshes the one it brings back, evicted while inactive, once`() async throws {
        let (state, tasks) = makeState()
        defer { state.shutdown() }
        try await open(in: state, tasks: tasks)
        try await open("short", path: "/project/short.txt", in: state, tasks: tasks)
        state.switchToTab(0)
        state.switchToTab(1)
        let passes = state.highlightGeneration

        state.closeCurrentTab()

        #expect(state.filePath == "/project/wide.txt")
        #expect(state.highlightGeneration == passes + 1)
        #expect(state.highlightedLines.count == Self.lines.count)
        #expect(state.highlightedLines[0].map(\.text).joined() == Self.lines[0])
    }

    @Test
    func `closing a tab keeps the highlights and width of the one it brings back when it has them`() async throws {
        let (state, tasks) = makeState()
        defer { state.shutdown() }
        try await open(in: state, tasks: tasks)
        // An open leaves the first tab with its highlights and width.
        try await open("short", path: "/project/short.txt", in: state, tasks: tasks)
        let highlights = state.bufferManager.buffers[0].highlightedLines
        let passes = state.highlightGeneration

        state.closeCurrentTab()

        #expect(state.filePath == "/project/wide.txt")
        #expect(state.highlightGeneration == passes)
        #expect(state.highlightedLines == highlights)
        #expect(state.maxLineWidth == Self.widestLine.count)
    }
}

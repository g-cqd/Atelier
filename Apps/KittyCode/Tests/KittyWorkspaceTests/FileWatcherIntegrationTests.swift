import AemiTesting
import AtelierText
import Foundation
import KittyFileTree
import Testing

@testable import KittyWorkspace

/// A watcher that reports exactly what a test sends, canonical paths included, as FSEvents would.
final class FakeFileWatcher: FileWatching {
    let events: AsyncStream<FileWatcher.FileWatchEvent>
    private let continuation: AsyncStream<FileWatcher.FileWatchEvent>.Continuation

    init() {
        (events, continuation) = AsyncStream.makeStream()
    }

    func watchDirectory(_ path: String) async {}
    func watchFile(_ path: String) async {}
    func unwatchFile(_ path: String) async {}
    func suppressNotifications(for path: String) {}

    func stop() async {
        continuation.finish()
    }

    func send(_ event: FileWatcher.FileWatchEvent) {
        continuation.yield(event)
    }
}

/// Records each call the integration makes, in order, so a test can wait for one.
@MainActor
final class WatcherDelegateSpy: FileWatcherDelegate {
    let calls = CountProbe<String>()

    func fileWatcherDidDetectDirectoryChange() async {
        calls.record("directory")
    }

    func fileWatcherDidDetectExternalModification(bufferName: String) {
        calls.record("external \(bufferName)")
    }

    func fileWatcherDidReloadActiveBuffer(buffer: DocumentBuffer, content: String) {
        calls.record("reload active \(buffer.fileName)")
    }

    func fileWatcherDidReloadInactiveBuffer(buffer: DocumentBuffer, content: String) {
        calls.record("reload inactive \(buffer.fileName)")
    }
}

/// A workspace over a fresh directory holding `notes.txt`, opened inactive behind an active scratch buffer, and the
/// integration and autosave wired to it through a fake watcher.
@MainActor
struct WatchedWorkspace {
    let root: String
    let path: String
    let workspace: WorkspaceSession
    let notes: DocumentBuffer
    let watcher = FakeFileWatcher()
    let delegate = WatcherDelegateSpy()
    let taskProvider = TaskProviderSpy()
    let integration: FileWatcherIntegration

    init(content: String, lineEnding: TextDocument.LineEnding = .lineFeed) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        path = root + "/notes.txt"
        let bytes = TextDocument.serializedText(from: content, lineEnding: lineEnding)
        try Data(bytes.utf8).write(to: URL(fileURLWithPath: path))
        workspace = WorkspaceSession(rootPath: root)
        workspace.bufferManager.open(
            filePath: path, fileName: "notes.txt", content: content, language: nil, lineEnding: lineEnding)
        workspace.bufferManager.open(
            filePath: root + "/scratch.txt", fileName: "scratch.txt", content: "", language: nil)
        notes = workspace.bufferManager.buffers[0]
        notes.lastModifiedDate = WorkspaceFileLoading.modificationDate(ofFileAt: path)
        integration = FileWatcherIntegration(
            watcher: watcher, workspace: workspace, delegate: delegate, offloadFileRead: { read in try read() },
            taskProvider: taskProvider)
    }

    /// The path FSEvents reports for `notes.txt`: under `/private/var/...` where the buffer says `/var/...`.
    var canonicalPath: String {
        FileWatcher.canonicalPaths(forFile: path)[0]
    }

    /// Edits `notes.txt` in its buffer as typing would: a recorded undo step, a new version, dirty.
    func edit(to text: String) {
        let before = BufferEditSnapshot(
            textBuffer: notes.textBuffer, textCursor: notes.textCursor, lineEnding: notes.lineEnding)
        notes.textBuffer = TextBuffer(text)
        let after = BufferEditSnapshot(
            textBuffer: notes.textBuffer, textCursor: notes.textCursor, lineEnding: notes.lineEnding)
        notes.editHistory.recordChange(from: before, to: after, coalescingWindow: nil)
        notes.documentVersion += 1
        notes.isDirty = notes.editHistory.isDirty(current: after)
    }

    func autoSave(
        offloadDiskWrite: @escaping BlockingDiskWrite = { write in try write() },
        reportFailure: @escaping @MainActor (String) -> Void = { _ in }
    ) -> AutoSaveManager {
        AutoSaveManager(
            workspace: workspace, fileWatcherIntegration: integration, autoSaveInterval: 1, saveActiveBuffer: {},
            offloadDiskWrite: offloadDiskWrite, reportFailure: reportFailure, taskProvider: taskProvider)
    }

    func removeDirectory() {
        try? FileManager.default.removeItem(atPath: root)
    }
}

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct FileWatcherIntegrationTests {
    @Test func `an external append after an atomic save reloads the buffer, and the save's own echo flags nothing`()
        async throws
    {
        let sut = try WatchedWorkspace(content: "one\n")
        defer { sut.removeDirectory() }
        sut.integration.start()
        sut.edit(to: "one\nedited\n")
        sut.autoSave().saveAllDirtyBuffers()
        try await sut.taskProvider.waitForAllTasks(timeout: .seconds(15))
        #expect(!sut.notes.isDirty)

        // The echo of the autosave's own atomic write, reported canonically, then a marker event.
        sut.watcher.send(.directoryChanged(sut.canonicalPath))
        sut.watcher.send(.directoryChanged(CanonicalRoot.of(sut.root)))
        try await sut.delegate.calls.wait(forAtLeast: 2, timeout: .seconds(15))
        #expect(!sut.notes.externallyModified)
        #expect(sut.delegate.calls.events == ["directory", "directory"])

        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: sut.path))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("appended\n".utf8))
        try handle.close()
        sut.watcher.send(.fileChanged(sut.canonicalPath))
        try await sut.delegate.calls.wait(forAtLeast: 3, timeout: .seconds(15))

        #expect(sut.delegate.calls.events.last == "reload inactive notes.txt")
        #expect(sut.notes.textBuffer.text == "one\nedited\nappended\n")
        #expect(!sut.notes.isDirty)
    }

    @Test func `a watcher event during a background save waits for the save instead of flagging its own write`()
        async throws
    {
        let sut = try WatchedWorkspace(content: "one\n")
        defer { sut.removeDirectory() }
        sut.integration.start()
        sut.edit(to: "one\nedited\n")
        let written = CountProbe<Never>()
        let gate = TaskGate()
        let autoSave = sut.autoSave(offloadDiskWrite: { write in
            let date = try write()
            written.record()
            try await gate.wait()
            return date
        })
        autoSave.saveAllDirtyBuffers()
        try await written.wait(forAtLeast: 1, timeout: .seconds(15))

        // The write landed, but the buffer has not recorded it yet: the event must not read it as external.
        sut.watcher.send(.fileChanged(sut.path))
        sut.watcher.send(.directoryChanged(CanonicalRoot.of(sut.root)))
        try await sut.delegate.calls.wait(forAtLeast: 1, timeout: .seconds(15))
        #expect(!sut.notes.externallyModified)
        #expect(sut.notes.hasDiskCheckPending)

        gate.open()
        try await sut.taskProvider.waitForAllTasks(timeout: .seconds(15))
        #expect(!sut.notes.externallyModified)
        #expect(!sut.notes.hasDiskCheckPending)
        #expect(!sut.notes.isDirty)
    }

    @Test func `a dirty buffer whose file changed is flagged, not reloaded`() async throws {
        let sut = try WatchedWorkspace(content: "one\n")
        defer { sut.removeDirectory() }
        sut.integration.start()
        sut.edit(to: "one\nmine\n")
        try Data("theirs\n".utf8).write(to: URL(fileURLWithPath: sut.path))

        sut.watcher.send(.directoryChanged(sut.canonicalPath))
        try await sut.delegate.calls.wait(forAtLeast: 1, timeout: .seconds(15))

        #expect(sut.notes.externallyModified)
        #expect(sut.notes.textBuffer.text == "one\nmine\n")
    }
}

/// The canonical spelling of an existing directory, as FSEvents reports it.
enum CanonicalRoot {
    static func of(_ directory: String) -> String {
        FileWatcher.canonicalPaths(forFile: directory)[0]
    }
}

import AemiTesting
import AtelierText
import Foundation
import KittyFileTree
import Testing

@testable import KittyWorkspace

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct AutoSaveManagerTests {
    private func fileBytes(_ path: String) throws -> [UInt8] {
        Array(try Data(contentsOf: URL(fileURLWithPath: path)))
    }

    @Test func `an edit made while an inactive buffer is written leaves it unsaved`() async throws {
        let sut = try WatchedWorkspace(content: "one\n")
        defer { sut.removeDirectory() }
        sut.edit(to: "one\nsaved\n")
        let started = CountProbe<Never>()
        let gate = TaskGate()
        let autoSave = sut.autoSave(offloadDiskWrite: { write in
            started.record()
            try await gate.wait()
            return try write()
        })
        autoSave.saveAllDirtyBuffers()
        try await started.wait(forAtLeast: 1, timeout: .seconds(15))

        sut.edit(to: "one\nsaved\ntyped during the write\n")
        gate.open()
        try await sut.taskProvider.waitForAllTasks(timeout: .seconds(15))

        #expect(sut.notes.isDirty)
        #expect(try fileBytes(sut.path) == Array("one\nsaved\n".utf8))
    }

    @Test func `after an inactive autosave, undoing to the original text leaves the buffer unsaved against the file`()
        async throws
    {
        let sut = try WatchedWorkspace(content: "one\n")
        defer { sut.removeDirectory() }
        sut.edit(to: "one\nsaved\n")
        let autoSave = sut.autoSave()
        autoSave.saveAllDirtyBuffers()
        try await sut.taskProvider.waitForAllTasks(timeout: .seconds(15))
        #expect(!sut.notes.isDirty)

        let current = BufferEditSnapshot(
            textBuffer: sut.notes.textBuffer, textCursor: sut.notes.textCursor, lineEnding: sut.notes.lineEnding)
        guard case .applied(let original) = sut.notes.editHistory.undo(current: current) else {
            Issue.record("the edit should be undoable")
            return
        }

        #expect(original.textBuffer.text == "one\n")
        #expect(sut.notes.editHistory.isDirty(current: original))
    }

    @Test func `a failed inactive autosave shows a message and leaves the buffer unsaved`() async throws {
        let sut = try WatchedWorkspace(content: "one\n")
        defer { sut.removeDirectory() }
        sut.edit(to: "one\nlost?\n")
        let messages = CountProbe<String>()
        let autoSave = sut.autoSave(
            offloadDiskWrite: { _ in throw CocoaError(.fileWriteNoPermission) },
            reportFailure: { messages.record($0) })
        autoSave.saveAllDirtyBuffers()
        try await messages.wait(forAtLeast: 1, timeout: .seconds(15))

        #expect(messages.events.first?.hasPrefix("Autosave failed for notes.txt") == true)
        #expect(sut.notes.isDirty)
        #expect(!sut.notes.isSavingInBackground)
    }

    @Test func `autosave skips a buffer whose file changed on disk since it was read`() async throws {
        let sut = try WatchedWorkspace(content: "one\n")
        defer { sut.removeDirectory() }
        sut.edit(to: "one\nmine\n")
        // Written behind the editor's back, with no watcher event to flag it: only its modification date tells.
        try Data("theirs\n".utf8).write(to: URL(fileURLWithPath: sut.path))
        let writes = CountProbe<Never>()
        let autoSave = sut.autoSave(offloadDiskWrite: { write in
            writes.record()
            return try write()
        })
        autoSave.saveAllDirtyBuffers()
        try await sut.taskProvider.waitForAllTasks(timeout: .seconds(15))

        #expect(writes.isEmpty)
        #expect(try fileBytes(sut.path) == Array("theirs\n".utf8))
        #expect(sut.notes.isDirty)
    }

    @Test func `an inactive autosave writes the buffer's own line ending`() async throws {
        let sut = try WatchedWorkspace(content: "one\n", lineEnding: .carriageReturnLineFeed)
        defer { sut.removeDirectory() }
        sut.edit(to: "one\ntwo\n")
        let autoSave = sut.autoSave()
        autoSave.saveAllDirtyBuffers()
        try await sut.taskProvider.waitForAllTasks(timeout: .seconds(15))

        #expect(try fileBytes(sut.path) == Array("one\r\ntwo\r\n".utf8))
    }
}

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct WatchedFileMonitorTests {
    @Test func `the monitored file reports each atomic save by another editor`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let path = directory + "/config.json"
        try Data("{}".utf8).write(to: URL(fileURLWithPath: path))
        let changes = CountProbe<Never>()
        let monitor = WatchedFileMonitor(path: path, watcher: FileWatcher(), taskProvider: TaskProviderSpy()) {
            changes.record()
        }
        await monitor.start()

        // Another editor saves by writing a temporary file and renaming it over the original, a new inode each time.
        try Data("{\"a\":1}".utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
        try await changes.wait(forAtLeast: 1, timeout: .seconds(15))
        let afterFirstSave = changes.count
        try Data("{\"a\":2}".utf8).write(to: URL(fileURLWithPath: path), options: .atomic)
        try await changes.wait(forAtLeast: afterFirstSave + 1, timeout: .seconds(15))

        await monitor.stop()
    }

    @Test func `the monitor recognizes its file under a canonical directory path, and nothing else`() {
        let path = "/tmp/atelier-monitor-\(UUID().uuidString)/config.json"
        let monitor = WatchedFileMonitor(path: path, watcher: FakeFileWatcher(), taskProvider: TaskProviderSpy()) {}

        #expect(monitor.concerns(.fileChanged(path)))
        #expect(monitor.concerns(.directoryChanged("/private" + path)))
        #expect(!monitor.concerns(.directoryChanged("/private" + path + ".sb-temporary")))
        #expect(!monitor.concerns(.directoryChanged(path + "-sibling")))
    }
}

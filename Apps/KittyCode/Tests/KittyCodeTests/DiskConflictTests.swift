import AemiTesting
import AtelierText
import Foundation
import KittyCodecs
import KittyInput
import KittyRenderer
import KittyTerminal
import KittyWorkspace
import Testing

@testable import KittyEditor

/// A save never silently overwrites a change made outside the editor: it is refused with a way out, `:w!` and the
/// force-save command overwrite on purpose, and a reload takes the disk's text while undo keeps the edits.
@Suite(.timeLimit(.minutes(1)))
@MainActor
struct DiskConflictTests {
    /// An editor on a fresh directory with `notes.txt` open and edited, and the file then rewritten behind its back.
    private struct Conflict {
        let root: String
        let path: String
        let state: EditorState
        let taskProvider: TaskProviderSpy

        func removeDirectory() {
            try? FileManager.default.removeItem(atPath: root)
        }

        func fileText() throws -> String {
            try String(contentsOfFile: path, encoding: .utf8)
        }
    }

    private func makeConflict(keybindingMode: KittyConfig.KeybindingMode = .nano) async throws -> Conflict {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        let path = root + "/notes.txt"
        try Data("original\n".utf8).write(to: URL(fileURLWithPath: path))
        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbon.position = .hidden
        config.syntax.enabled = false
        config.keybindingMode = keybindingMode
        let taskProvider = TaskProviderSpy()
        let state = EditorState(rootPath: root, config: config, taskProvider: taskProvider)
        state.openFilePath(path, name: "notes.txt")
        try await taskProvider.waitForAllTasks(timeout: .seconds(30))
        insertText("mine ", into: state)
        try Data("theirs\n".utf8).write(to: URL(fileURLWithPath: path))
        return Conflict(root: root, path: path, state: state, taskProvider: taskProvider)
    }

    @Test func `saving over a file changed on disk is refused and names the way out`() async throws {
        let conflict = try await makeConflict()
        defer { conflict.removeDirectory() }

        #expect(!conflict.state.saveFile())
        #expect(try conflict.fileText() == "theirs\n")
        #expect(
            conflict.state.statusMessage
                == "notes.txt changed on disk: Ctrl+Shift+O overwrites it, Ctrl+Shift+R reloads it")
        #expect(conflict.state.bufferManager.activeBuffer?.isDirty == true)
    }

    @Test func `a buffer the watcher flagged is refused even when the dates agree`() async throws {
        let conflict = try await makeConflict()
        defer { conflict.removeDirectory() }
        let buffer = try #require(conflict.state.bufferManager.activeBuffer)
        buffer.lastModifiedDate = WorkspaceFileLoading.modificationDate(ofFileAt: conflict.path)
        buffer.externallyModified = true

        #expect(!conflict.state.saveFile())
        #expect(try conflict.fileText() == "theirs\n")
    }

    @Test func `the force-save command overwrites a file changed on disk`() async throws {
        let conflict = try await makeConflict()
        defer { conflict.removeDirectory() }
        let pipeline = RenderPipeline(
            connection: MockTerminalConnection(size: TerminalSize(columns: 80, rows: 24)), columns: 80, rows: 24)

        #expect(dispatchCommand(.forceSaveFile, state: conflict.state, pipeline: pipeline))
        #expect(try conflict.fileText() == "mine original\n")
        #expect(conflict.state.bufferManager.activeBuffer?.isDirty == false)
        // Saved: the next plain save goes through.
        #expect(conflict.state.saveFile())
    }

    @Test func `:w! overwrites a file changed on disk`() async throws {
        let conflict = try await makeConflict(keybindingMode: .vim)
        defer { conflict.removeDirectory() }

        #expect(conflict.state.executeVimExCommand("w!"))
        #expect(try conflict.fileText() == "mine original\n")
    }

    @Test func `a refused :wq stays in the editor and shows why`() async throws {
        let conflict = try await makeConflict(keybindingMode: .vim)
        defer { conflict.removeDirectory() }
        conflict.state.mode = .editor

        #expect(conflict.state.executeVimExCommand("wq"))
        #expect(conflict.state.mode == .editor)
        #expect(conflict.state.statusMessage == "notes.txt changed on disk: :w! overwrites it, :e! reloads it")
        #expect(try conflict.fileText() == "theirs\n")
    }

    @Test func `saving as another existing file is never refused`() async throws {
        let conflict = try await makeConflict()
        defer { conflict.removeDirectory() }
        let other = conflict.root + "/other.txt"
        try Data("someone else's\n".utf8).write(to: URL(fileURLWithPath: other))

        #expect(conflict.state.writeBufferToDisk(at: other))
        #expect(try String(contentsOfFile: other, encoding: .utf8) == "mine original\n")
        #expect(try conflict.fileText() == "theirs\n")
    }

    @Test func `a reload takes the file's text, and undo brings the edits back unsaved`() async throws {
        let conflict = try await makeConflict()
        defer { conflict.removeDirectory() }

        conflict.state.reloadActiveBufferFromDisk()
        try await conflict.taskProvider.waitForAllTasks(timeout: .seconds(30))
        let buffer = try #require(conflict.state.bufferManager.activeBuffer)
        #expect(conflict.state.documentText == "theirs\n")
        #expect(!buffer.isDirty)
        #expect(!buffer.conflictsWithDisk())

        conflict.state.undoActiveBuffer()
        #expect(conflict.state.documentText == "mine original\n")
        #expect(buffer.isDirty)
    }

    @Test func `:e! reloads the buffer from its file`() async throws {
        let conflict = try await makeConflict(keybindingMode: .vim)
        defer { conflict.removeDirectory() }

        #expect(conflict.state.executeVimExCommand("e!"))
        try await conflict.taskProvider.waitForAllTasks(timeout: .seconds(30))
        #expect(conflict.state.documentText == "theirs\n")
    }

    @Test func `a buffer still being written in the background refuses a save over its file`() async throws {
        let conflict = try await makeConflict()
        defer { conflict.removeDirectory() }
        let buffer = try #require(conflict.state.bufferManager.activeBuffer)
        buffer.isSavingInBackground = true

        #expect(!conflict.state.saveFile(overwritingDiskChanges: true))
        #expect(try conflict.fileText() == "theirs\n")
    }

    @Test(arguments: [KittyConfig.KeybindingMode.nano, .vim, .kittycode])
    func `every keymap binds the force-save and reload commands`(mode: KittyConfig.KeybindingMode) {
        var config = KittyConfig()
        config.keybindingMode = mode
        let resolver = KeymapResolver(config: config)
        let forceSave = KeyStroke(keyCode: AsciiKey.o, modifiers: [.ctrl, .shift])
        let reload = KeyStroke(keyCode: UInt32(UInt8(ascii: "r")), modifiers: [.ctrl, .shift])

        #expect(resolver.resolve(forceSave, context: .editor) == .forceSaveFile)
        #expect(resolver.resolve(reload, context: .editor) == .reloadFromDisk)
    }
}

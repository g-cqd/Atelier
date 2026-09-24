import AemiTesting
import AtelierText
import Foundation
import KittyWorkspace
import Testing

@testable import KittyEditor

/// Files keep their line endings, byte for byte, across open, edit and save: each save of a CRLF file used to add a CR
/// per line (`61 0d 0d 0a` after one save).
@Suite
@MainActor
struct LineEndingRoundTripTests {
    /// An editor on `root` whose open-file work the returned spy tracks.
    private func makeEditor(root: String) -> (state: EditorState, taskProvider: TaskProviderSpy) {
        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbon.position = .hidden
        config.syntax.enabled = false
        let taskProvider = TaskProviderSpy()
        return (
            EditorState(rootPath: root, config: config, taskProvider: taskProvider, searchPool: EditorTestPool.shared),
            taskProvider
        )
    }

    private func bytes(at path: String) throws -> [UInt8] {
        Array(try Data(contentsOf: URL(fileURLWithPath: path)))
    }

    @Test(arguments: [TextDocument.LineEnding.lineFeed, .carriageReturnLineFeed, .carriageReturn])
    func `three open, edit and save cycles keep the file's line ending byte for byte`(
        lineEnding: TextDocument.LineEnding
    ) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: root) }
        let path = root + "/notes.txt"
        let ending = lineEnding.sequence
        try Data(("a" + ending + "b" + ending).utf8).write(to: URL(fileURLWithPath: path))

        for cycle in 1 ... 3 {
            let editor = makeEditor(root: root)
            editor.state.openFilePath(path, name: "notes.txt")
            try await editor.taskProvider.waitForAllTasks(timeout: .seconds(30))
            // Two lines and the empty one after the last break, whichever ending splits them.
            #expect(editor.state.fileLineCount == 3, "cycle \(cycle)")
            insertText("x", into: editor.state)

            #expect(editor.state.writeBufferToDisk(at: path))
            let expected = String(repeating: "x", count: cycle) + "a" + ending + "b" + ending
            #expect(try bytes(at: path) == Array(expected.utf8), "cycle \(cycle)")
        }
    }

    @Test func `saving an unedited CRLF file leaves its bytes identical`() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: root) }
        let path = root + "/notes.txt"
        let original: [UInt8] = [0x61, 0x0D, 0x0A, 0x62, 0x0D, 0x0A]
        try Data(original).write(to: URL(fileURLWithPath: path))
        let editor = makeEditor(root: root)
        editor.state.openFilePath(path, name: "notes.txt")
        try await editor.taskProvider.waitForAllTasks(timeout: .seconds(30))

        #expect(editor.state.fileContent == ["a", "b", ""])
        #expect(editor.state.writeBufferToDisk(at: path))
        #expect(try bytes(at: path) == original)
    }
}

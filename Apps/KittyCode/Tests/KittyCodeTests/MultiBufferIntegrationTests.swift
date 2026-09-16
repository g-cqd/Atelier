import AtelierText
import Foundation
import KittyCodecs
import KittyFileTree
import KittyGit
import KittyRenderer
import KittySyntax
import KittyTerminal
import KittyWidgets
import KittyWorkspace
import Testing

@testable import KittyEditor

@Suite
@MainActor
struct MultiBufferIntegrationTests {
    @Test
    func `switching tabs preserves cursor position`() {
        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbon.position = .hidden
        let state = EditorState(rootPath: ".", config: config)

        // Simulate opening first file via bufferManager
        state.bufferManager.open(
            filePath: "/a.txt", fileName: "a.txt", content: "hello world", language: nil)
        state.restoreStateFromActiveBuffer()
        state.cursorRow = 0
        state.cursorCol = 5

        // Simulate opening second file
        state.saveStateToActiveBuffer()
        state.bufferManager.open(
            filePath: "/b.txt", fileName: "b.txt", content: "line1\nline2\nline3", language: nil)
        state.restoreStateFromActiveBuffer()
        state.cursorRow = 2
        state.cursorCol = 3

        // Switch back to first file
        state.switchToTab(0)
        #expect(state.cursorRow == 0)
        #expect(state.cursorCol == 5)
        #expect(state.fileName == "a.txt")

        // Switch back to second file
        state.switchToTab(1)
        #expect(state.cursorRow == 2)
        #expect(state.cursorCol == 3)
        #expect(state.fileName == "b.txt")
    }

    @Test
    func `switching tabs isolates selection state per buffer`() {
        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbon.position = .hidden
        let state = EditorState(rootPath: ".", config: config)

        state.bufferManager.open(
            filePath: "/a.txt",
            fileName: "a.txt",
            content: "alpha\nbeta\ngamma",
            language: nil
        )
        state.restoreStateFromActiveBuffer()
        let firstSelection = TextSelection(
            anchor: TextPosition(row: 1, col: 1),
            head: TextPosition(row: 2, col: 3)
        )
        state.selection = firstSelection

        state.saveStateToActiveBuffer()
        state.bufferManager.open(
            filePath: "/b.txt",
            fileName: "b.txt",
            content: "short",
            language: nil
        )
        state.restoreStateFromActiveBuffer()

        #expect(state.fileName == "b.txt")
        #expect(state.selection == nil)

        state.switchToTab(0)
        #expect(state.fileName == "a.txt")
        #expect(state.selection == firstSelection)

        state.switchToTab(1)
        #expect(state.fileName == "b.txt")
        #expect(state.selection == nil)
    }

    @Test
    func `textDidChange marks active buffer dirty`() {
        var config = KittyConfig()
        config.activityBar.show = false
        let state = EditorState(rootPath: ".", config: config)

        state.bufferManager.open(
            filePath: "/a.txt", fileName: "a.txt", content: "hello", language: nil)
        state.restoreStateFromActiveBuffer()
        #expect(state.bufferManager.activeBuffer?.isDirty == false)

        state.textDidChange()
        #expect(state.bufferManager.activeBuffer?.isDirty == true)
    }

    @Test
    @MainActor
    func `opening and restoring a file preserves exact document snapshots`() async throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent(
            UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: rootURL) }

        let firstFileURL = rootURL.appendingPathComponent("first.txt")
        let secondFileURL = rootURL.appendingPathComponent("second.txt")
        try "alpha\nbeta\n".write(to: firstFileURL, atomically: true, encoding: .utf8)
        try "gamma".write(to: secondFileURL, atomically: true, encoding: .utf8)

        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbon.position = .hidden
        let state = EditorState(rootPath: rootURL.path, config: config)

        func waitUntil(_ condition: @escaping () -> Bool) async {
            for _ in 0 ..< 200 {
                if condition() {
                    return
                }
                try? await Task.sleep(for: .milliseconds(5))
            }
            Issue.record("Timed out waiting for asynchronous file open")
        }

        state.openFilePath(firstFileURL.path, name: "first.txt")
        await waitUntil { state.fileName == "first.txt" }
        #expect(state.fileContent == ["alpha", "beta", ""])
        #expect(state.documentText == "alpha\nbeta\n")

        state.openFilePath(secondFileURL.path, name: "second.txt")
        await waitUntil { state.fileName == "second.txt" }
        state.switchToTab(0)

        #expect(state.fileName == "first.txt")
        #expect(state.fileContent == ["alpha", "beta", ""])
        #expect(state.documentText == "alpha\nbeta\n")
    }
}

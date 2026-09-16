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
struct StatusBarAndPromptTests {
    @Test
    func `beginSavePrompt defaults to last selected directory`() {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString, isDirectory: true)
        let state = EditorState(rootPath: rootURL.path, config: KittyConfig())

        state.noteSelectedPath(
            rootURL.appendingPathComponent("Sources/App/main.swift").path, isDirectory: false)
        state.beginNewFile()
        state.beginSavePrompt()

        #expect(state.prompt?.input == "Sources/App/")
    }

    @Test
    func `prompt accepts alt modified unicode fallback text`() {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        let pipeline = RenderPipeline(
            connection: MockTerminalConnection(size: TerminalSize(columns: 40, rows: 10)),
            columns: 40,
            rows: 10
        )

        state.beginNewFile()
        state.beginSavePrompt()

        let handled = handleEvent(
            event: .key(KeyEvent(keyCode: 0x00E9, modifiers: .alt)),
            state: state,
            pipeline: pipeline
        )

        #expect(handled)
        #expect(state.prompt?.input.hasSuffix("é") == true)
    }

    @Test
    func `statusBarSegments render configured file metadata`() {
        var config = KittyConfig()
        config.statusBar.leftItems = [.file]
        config.statusBar.rightItems = [.language, .lineEnding, .git, .position]

        let state = EditorState(rootPath: ".", config: config)
        state.beginNewFile()
        state.mode = .editor
        state.fileName = "note.swift"
        state.bufferManager.activeBuffer?.fileName = "note.swift"
        state.currentLanguage = "swift"
        state.currentLineEnding = .carriageReturnLineFeed
        state.fileContent = ["abc"]
        state.cursorRow = 0
        state.cursorCol = 2
        state.fileStatusProvider = TestGitProvider(
            summary: .init(modified: 3, added: 1, deleted: 2, conflicted: 1)
        )

        let segments = state.statusBarSegments(columns: 80, rows: 24)

        #expect(segments.left.contains("note.swift"))
        #expect(segments.right.contains("│"))
        #expect(segments.right.contains("swift"))
        #expect(segments.right.contains("CRLF"))
        #expect(segments.right.contains("M3 A1 D2 !1"))
        #expect(segments.right.contains("Ln 1, Col 3"))
    }

    @Test
    func `writeBufferToDisk preserves configured line endings`() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let state = EditorState(rootPath: rootURL.path, config: KittyConfig())
        state.beginNewFile()
        state.fileContent = ["alpha", "beta", ""]
        state.currentLineEnding = .carriageReturnLineFeed

        let savedURL = rootURL.appendingPathComponent("notes/output.txt")
        let saveSucceeded = state.writeBufferToDisk(at: savedURL.path)

        #expect(saveSucceeded)
        #expect(try String(contentsOf: savedURL, encoding: .utf8) == "alpha\r\nbeta\r\n")
        #expect(state.currentLineEnding == .carriageReturnLineFeed)
        #expect(state.bufferManager.activeBuffer?.lineEnding == .carriageReturnLineFeed)
    }
}

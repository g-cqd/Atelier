import Foundation
import KittyCodecs
import KittyFileTree
import KittyGit
import KittyRenderer
import KittySyntax
import KittyTerminal
import KittyText
import KittyWidgets
import KittyWorkspace
import Testing

@testable import KittyEditor

@Suite
@MainActor
struct ActivityBarAndFileLifecycleRegressionTests {
    private func makeSUT(
        fileContent: [String] = [""],
        columns: Int = 80,
        rows: Int = 24,
        activityBar: Bool = false,
        tabRibbon: KittyConfig.TabRibbonPosition = .hidden
    ) -> (state: EditorState, pipeline: RenderPipeline) {
        makeRuntimeRegressionContext(
            fileContent: fileContent,
            columns: columns,
            rows: rows,
            activityBar: activityBar,
            tabRibbon: tabRibbon
        )
    }

    @Test
    func `activity bar renders in the first 3 columns`() {
        let sut = makeSUT(fileContent: ["test"], columns: 40, rows: 10, activityBar: true)
        sut.state.mode = .editor
        renderShellLayout(pipeline: sut.pipeline, state: sut.state)

        // Activity bar renders at columns 0-2, contentStartRow=1
        // Column 1 (centered) should have an icon character for the first activity bar item
        let iconCell = sut.pipeline.buffer[1, 1]
        #expect(
            iconCell.character != " " || iconCell.style != .default,
            "Activity bar center column should have styled content")
    }

    @Test
    func `ActivityBar width is 3`() {
        #expect(ActivityBar.width == 3)
    }

    @Test
    func `ctrl n creates an editable untitled buffer`() {
        let sut = makeSUT(columns: 40, rows: 10)
        sut.state.mode = .tree
        sut.state.sidebarCollapsed = true

        let handled = handleEvent(
            event: .key(KeyEvent(keyCode: AsciiKey.n, modifiers: .ctrl)),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(handled)
        #expect(sut.state.bufferManager.count == 1)
        #expect(sut.state.fileName == "Untitled")
        #expect(sut.state.mode == .editor)

        renderShellLayout(pipeline: sut.pipeline, state: sut.state)

        #expect(sut.pipeline.cursorRow != nil)
        #expect(sut.pipeline.cursorCol != nil)
    }

    @Test
    func `save prompt writes a new file under the project root`() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbon.position = .hidden
        let state = EditorState(rootPath: rootURL.path, config: config)
        let pipeline = RenderPipeline(
            connection: MockTerminalConnection(size: TerminalSize(columns: 40, rows: 10)),
            columns: 40,
            rows: 10
        )

        state.beginNewFile()
        insertText("hello", into: state)

        let startedPrompt = handleEvent(
            event: .key(KeyEvent(keyCode: AsciiKey.o, modifiers: .ctrl)),
            state: state,
            pipeline: pipeline
        )
        let enteredPath = handleEvent(
            event: .key(KeyEvent(keyCode: 0, associatedText: "notes/new.txt")),
            state: state,
            pipeline: pipeline
        )
        let submittedPrompt = handleEvent(
            event: .key(KeyEvent(keyCode: Key.enter.rawValue)),
            state: state,
            pipeline: pipeline
        )

        let savedURL = rootURL.appendingPathComponent("notes/new.txt")

        #expect(startedPrompt)
        #expect(enteredPath)
        #expect(submittedPrompt)
        #expect(state.prompt == nil)
        #expect(state.filePath == savedURL.path)
        #expect(state.fileName == "new.txt")
        #expect(FileManager.default.fileExists(atPath: savedURL.path))
        #expect(try String(contentsOf: savedURL, encoding: .utf8) == "hello")
    }

    @Test
    func `dismissing prompt clears overlay chrome on next frame`() throws {
        let sut = makeSUT(columns: 40, rows: 10)
        sut.state.beginNewFile()
        sut.state.mode = .editor
        sut.state.beginSavePrompt()

        renderFrame(pipeline: sut.pipeline, state: sut.state)

        let promptCorner = try #require(
            (0 ..< 10).lazy
                .compactMap { row in
                    (0 ..< 40).lazy
                        .compactMap { col in
                            sut.pipeline.buffer[row, col].character == "┌" ? (row, col) : nil
                        }
                        .first
                }
                .first
        )

        sut.state.prompt = nil
        renderFrame(pipeline: sut.pipeline, state: sut.state)

        #expect(sut.pipeline.buffer[promptCorner.0, promptCorner.1].character != "┌")
    }
}

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
struct EditorContentLayoutRegressionTests {

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
    func `editor content renders at contentStartRow not row 1`() {
        let sut = makeSUT(fileContent: ["hello"], columns: 40, rows: 10)
        sut.state.mode = .editor
        sut.state.sidebarCollapsed = true
        sut.state.refreshHighlights()
        // Without tab ribbon, contentStartRow = 0
        renderShellLayout(pipeline: sut.pipeline, state: sut.state)

        // Without title bar, row 0 should have editor content (line numbers + text)
        let row1Chars = (0..<40).map { sut.pipeline.buffer[0, $0].character }
        let row1Text = String(row1Chars)
        #expect(
            row1Text.contains("hello"), "Editor content should appear at row 0 (contentStartRow)")
    }

    @Test
    func `editor content starts at row 2 when tab ribbon is shown`() {
        let cols = 40
        let sut = makeSUT(columns: cols, rows: 10, tabRibbon: .top)
        sut.state.mode = .editor
        sut.state.sidebarCollapsed = true
        sut.state.bufferManager.open(
            filePath: "/a.txt", fileName: "a.txt", content: "world", language: nil)
        sut.state.restoreStateFromActiveBuffer()
        sut.state.refreshHighlights()

        renderShellLayout(pipeline: sut.pipeline, state: sut.state)

        // Row 0: tab ribbon, Row 1: editor content
        let row2Chars = (0..<cols).map { sut.pipeline.buffer[1, $0].character }
        let row2Text = String(row2Chars)
        #expect(
            row2Text.contains("world"), "Editor content should appear at row 1 below tab ribbon")

        // Row 0 should NOT contain editor content (it's the tab ribbon)
        let row1Chars = (0..<cols).map { sut.pipeline.buffer[0, $0].character }
        let row1Text = String(row1Chars)
        #expect(!row1Text.contains("world"), "Tab ribbon row should not contain editor text")
    }

    @Test
    func `tab ribbon fills full terminal width`() {
        let cols = 40
        let sut = makeSUT(fileContent: ["x"], columns: cols, rows: 10, tabRibbon: .top)
        sut.state.bufferManager.open(
            filePath: "/a.txt", fileName: "a.txt", content: "x", language: nil)
        sut.state.restoreStateFromActiveBuffer()

        renderShellLayout(pipeline: sut.pipeline, state: sut.state)

        // Row 1 is the tab ribbon — every column should be non-null (filled with background)
        for col in 0..<cols {
            let cell = sut.pipeline.buffer[1, col]
            #expect(cell.character != "\0", "Tab ribbon row should be filled at col \(col)")
        }
    }

    @Test
    func `empty editor message renders at contentStartRow not row 1`() {
        let sut = makeSUT(columns: 60, rows: 10, tabRibbon: .top)
        sut.state.mode = .editor
        sut.state.sidebarCollapsed = true
        // With tab ribbon but no buffers, showTabRibbon=false (count=0)
        // So contentStartRow=1. Let's just verify render doesn't crash
        renderShellLayout(pipeline: sut.pipeline, state: sut.state)

        // No tab ribbon (no buffers), content starts at row 0
        // The empty editor message should be somewhere in the middle rows
        let midRow = 0 + (10 - 1) / 2  // contentStartRow + contentRows/2
        let rowChars = (0..<60).map { sut.pipeline.buffer[midRow, $0].character }
        let rowText = String(rowChars).trimmingCharacters(in: .whitespaces)
        #expect(rowText.contains("Open a file"))
    }

    @Test
    func `status bar renders on the last row`() {
        let rows = 10
        let sut = makeSUT(fileContent: ["test"], columns: 40, rows: rows)
        sut.state.mode = .editor
        renderShellLayout(pipeline: sut.pipeline, state: sut.state)

        let lastRowChars = (0..<40).map { sut.pipeline.buffer[rows - 1, $0].character }
        let lastRowText = String(lastRowChars)
        // Status bar should contain file name or language
        #expect(lastRowText.contains("Untitled") || lastRowText.contains("plain text"))
    }

    @Test
    func `no empty blank row between content and status bar`() {
        let rows = 10
        let sut = makeSUT(fileContent: (0..<20).map { "line \($0)" }, columns: 40, rows: rows)
        sut.state.mode = .editor
        renderShellLayout(pipeline: sut.pipeline, state: sut.state)

        // Row rows-2 (second to last) should have editor content, not be blank
        let penultimateChars = (0..<40).map { sut.pipeline.buffer[rows - 2, $0].character }
        let penultimateText = String(penultimateChars).trimmingCharacters(in: .whitespaces)
        #expect(!penultimateText.isEmpty, "Second-to-last row should have content, not be blank")
    }

    @Test
    func `full layout with activity bar and tab ribbon renders without overlap`() {
        let sut = makeSUT(
            fileContent: ["hello world"],
            columns: 60,
            rows: 12,
            activityBar: true,
            tabRibbon: .top
        )
        sut.state.mode = .editor
        sut.state.treePanelWidth = 15
        sut.state.bufferManager.open(
            filePath: "/a.txt", fileName: "a.txt", content: "hello world", language: nil)
        sut.state.restoreStateFromActiveBuffer()

        renderShellLayout(pipeline: sut.pipeline, state: sut.state)

        // Row 0: tab ribbon (full width)
        // Rows 1-10: activity bar (cols 0-2) + sidebar (cols 3-17) + separator (col 18) + editor (cols 19+)
        // Row 11: status bar

        // Tab ribbon at row 0
        let tabChar = sut.pipeline.buffer[0, 0].character
        #expect(tabChar != "\0", "Tab ribbon should fill from column 0")

        // Editor content at row 1 (contentStartRow=1)
        let editorArea = (19..<60).map { sut.pipeline.buffer[1, $0].character }
        let editorText = String(editorArea).trimmingCharacters(in: .whitespaces)
        #expect(
            editorText.contains("hello") || editorText.contains("1"),
            "Editor area should have content at row 1")

        // Status bar at last row
        let statusChars = (0..<60).map { sut.pipeline.buffer[11, $0].character }
        let statusText = String(statusChars)
        #expect(statusText.contains("a.txt") || statusText.contains("plain text"))
    }

    @Test
    func `toggling sidebar resets layout cleanly on re-render`() {
        let sut = makeSUT(fileContent: ["content line"], columns: 40, rows: 10)
        sut.state.mode = .editor
        sut.state.treePanelWidth = 10

        // Render with sidebar
        sut.state.sidebarCollapsed = false
        renderFrame(pipeline: sut.pipeline, state: sut.state)

        // Re-render without sidebar using the same top-level entry point as the app.
        sut.state.sidebarCollapsed = true
        renderFrame(pipeline: sut.pipeline, state: sut.state)

        // The separator column from the previous render should not persist
        // Editor should now start at column 0 (no sidebar)
        let row1Chars = (0..<40).map { sut.pipeline.buffer[0, $0].character }
        let row1Text = String(row1Chars).trimmingCharacters(in: .whitespaces)
        #expect(
            row1Text.contains("content") || row1Text.contains("1"),
            "Editor should render from column 0 when sidebar is collapsed")
    }
}

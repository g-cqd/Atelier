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

@testable import KittyCode

@Suite
@MainActor
struct WordAndViewportNavigationTests {

    private func makeSUT(fileContent: [String], columns: Int = 80, rows: Int = 24) -> (
        state: EditorState, pipeline: RenderPipeline
    ) {
        makeKittyCodeNavigationContext(fileContent: fileContent, columns: columns, rows: rows)
    }

    @Test
    func `Word jump forward moves to next token`() {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        state.fileContent = ["alpha   beta"]
        state.cursorRow = 0
        state.cursorCol = 0

        jumpWordForward(state: state)
        #expect(state.cursorCol == 8)
    }

    @Test
    func `Word jump backward moves to previous token start`() {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        state.fileContent = ["alpha   beta"]
        state.cursorRow = 0
        state.cursorCol = 12

        jumpWordBackward(state: state)
        #expect(state.cursorCol == 8)
    }

    @Test
    func `ensureEditorVisible updates horizontal scroll`() {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        state.fileContent = ["0123456789abcdefghijklmnopqrstuvwxyz"]
        state.cursorRow = 0
        state.cursorCol = 25
        state.hScrollOffset = 0
        state.config.editor.wrapLines = false

        ensureEditorVisible(state, contentRows: 10, availWidth: 8)
        #expect(state.hScrollOffset > 0)
        #expect(state.hScrollOffset == 18)
    }

    @Test
    func `ensureTreeVisible scrolls selected row into viewport`() {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        // Populate the underlying FileNode tree and flatten it
        state.treeNodes = (0..<40).map { i in
            FileNode(name: "f\(i)", path: "p\(i)", isDirectory: false)
        }
        state.cachedFlatTree = FileTreeNavigator.flatten(state.treeNodes)
        state.selectedTreeIndex = 25
        state.treeScrollOffset = 0

        ensureTreeVisible(state, contentRows: 10)
        #expect(state.treeScrollOffset == 16)
    }

    @Test
    func `scrollLinesPerTick scales with viewport height`() {
        #expect(scrollLinesPerTick(visibleRows: 10, configured: nil) == 3)
        #expect(scrollLinesPerTick(visibleRows: 24, configured: nil) == 3)
        #expect(scrollLinesPerTick(visibleRows: 48, configured: nil) == 6)
        #expect(scrollLinesPerTick(visibleRows: 200, configured: nil) == 12)
    }

    @Test
    func `scrollLinesPerTick respects configured value`() {
        #expect(scrollLinesPerTick(visibleRows: 48, configured: 1) == 1)
        #expect(scrollLinesPerTick(visibleRows: 48, configured: 20) == 20)
        #expect(scrollLinesPerTick(visibleRows: 48, configured: 0) == 6)
    }

    @Test
    func `tree panel scrollbar drag preserves existing mapping`() {
        let rect = Rect(x: 1, y: 1, width: 10, height: 5)

        #expect(TreePanelLayout.contentWidth(rowCount: 20, in: rect) == 9)
        #expect(
            TreePanelLayout.verticalScrollIndicatorRect(rowCount: 20, in: rect)
                == Rect(x: 10, y: 1, width: 1, height: 5))

        let gripOffset = TreePanelLayout.scrollGripOffset(
            rowCount: 20,
            scrollOffset: 0,
            in: rect,
            pointerRow: 2
        )

        #expect(gripOffset == 1)
        #expect(
            TreePanelLayout.scrollOffset(
                rowCount: 20,
                currentOffset: 0,
                in: rect,
                pointerRow: 5,
                gripOffset: gripOffset ?? 0
            ) == 19
        )
    }

    @Test
    func `editing a shorter line keeps the file max line width for horizontal scrolling`() {
        let sut = makeSUT(
            fileContent: [
                "0123456789abcdefghijklmnopqrstuvwxyz",
                "short",
            ],
            columns: 18,
            rows: 8
        )
        sut.state.cursorRow = 1
        sut.state.cursorCol = 5
        let initialMaxLineWidth = sut.state.maxLineWidth

        insertText("!", into: sut.state)

        let layout = LayoutMetrics(
            state: sut.state, columns: sut.pipeline.columns, rows: sut.pipeline.rows)
        let editorRect = Rect(
            x: layout.editorStart,
            y: layout.contentStartRow,
            width: layout.editorWidth,
            height: layout.contentRows
        )

        #expect(sut.state.maxLineWidth == initialMaxLineWidth)
        #expect(
            TextEditorLayout.needsHorizontalScrollIndicator(
                for: makeEditorView(state: sut.state),
                in: editorRect,
                maxLineWidth: sut.state.maxLineWidth
            )
        )
    }
}

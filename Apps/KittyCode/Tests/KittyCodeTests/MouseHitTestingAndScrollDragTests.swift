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
struct MouseHitTestingAndScrollDragTests {
    private func makeSUT(fileContent: [String], columns: Int = 80, rows: Int = 24) -> (
        state: EditorState, pipeline: RenderPipeline
    ) {
        makeKittyCodeNavigationContext(fileContent: fileContent, columns: columns, rows: rows)
    }

    @Test
    func `mouse click on wrapped editor row uses shared widget hit testing`() {
        let sut = makeSUT(fileContent: ["abcdef"], columns: 11, rows: 6)
        sut.state.config.editor.wrapLines = true
        sut.state.treePanelWidth = 3
        sut.state.mode = .editor

        handleMouse(
            MouseEvent(button: .left, row: 2, col: 9, kind: .press),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(sut.state.cursorRow == 0)
        // Content width is 4 (no scrollbar since 1 line fits in 4-row viewport),
        // so "abcdef" wraps as "abcd"+"ef"; click at wrap row 1, col 1 → char 5.
        #expect(sut.state.cursorCol == 5)
    }

    @Test
    func `double click on wrapped content selects the clicked word`() {
        let sut = makeSUT(fileContent: ["alpha beta gamma"], columns: 11, rows: 6)
        sut.state.config.editor.wrapLines = true
        sut.state.treePanelWidth = 3
        sut.state.mode = .editor
        sut.state.bufferManager.open(
            filePath: "/a.txt",
            fileName: "a.txt",
            content: "alpha beta gamma",
            language: nil
        )
        sut.state.restoreStateFromActiveBuffer()
        sut.state.lastClickTime = .now

        handleMouse(
            MouseEvent(button: .left, row: 3, col: 9, kind: .press),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(
            sut.state.selection
                == TextSelection(
                    anchor: TextPosition(row: 0, col: 6),
                    head: TextPosition(row: 0, col: 10)
                ))
    }

    @Test
    func `dragging the editor scroll indicator updates the shared scroll offset`() {
        let sut = makeSUT(fileContent: (0 ..< 20).map(String.init), columns: 18, rows: 8)
        sut.state.treePanelWidth = 3
        sut.state.mode = .editor

        handleMouse(
            MouseEvent(button: .left, row: 2, col: 18, kind: .press),
            state: sut.state,
            pipeline: sut.pipeline
        )
        handleMouse(
            MouseEvent(button: .left, row: 6, col: 18, kind: .drag),
            state: sut.state,
            pipeline: sut.pipeline
        )
        handleMouse(
            MouseEvent(button: .release, row: 6, col: 18, kind: .release),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(sut.state.scrollOffset == 19)
        #expect(sut.state.scrollDragState == nil)
        #expect(sut.state.mode == .editor)
    }

    @Test
    func `dragging the tree scroll indicator updates the tree scroll offset`() {
        let sut = makeSUT(fileContent: [""], columns: 18, rows: 8)
        sut.state.treePanelWidth = 5
        sut.state.mode = .tree
        sut.state.treeNodes = (0 ..< 30)
            .map { i in
                FileNode(name: "f\(i)", path: "p\(i)", isDirectory: false)
            }
        sut.state.cachedFlatTree = FileTreeNavigator.flatten(sut.state.treeNodes)

        // Tree indicator is at col 5 (treeWidth = min(5, 9) = 5, treeRect.maxX - 1 = 5)
        handleMouse(
            MouseEvent(button: .left, row: 2, col: 5, kind: .press),
            state: sut.state,
            pipeline: sut.pipeline
        )
        #expect(sut.state.scrollDragState != nil)

        handleMouse(
            MouseEvent(button: .left, row: 6, col: 5, kind: .drag),
            state: sut.state,
            pipeline: sut.pipeline
        )
        handleMouse(
            MouseEvent(button: .release, row: 6, col: 5, kind: .release),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(sut.state.treeScrollOffset > 0)
        #expect(sut.state.scrollDragState == nil)
        #expect(sut.state.mode == .tree)
    }
}

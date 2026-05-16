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
struct MouseAndContextMenuRegressionTests {

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
    func `editor click converts 1-based mouse coordinates correctly`() {
        let sut = makeSUT(
            fileContent: ["line one", "line two", "line three"], columns: 40, rows: 10)
        sut.state.mode = .editor
        sut.state.treePanelWidth = 0
        sut.state.sidebarCollapsed = true

        // Mouse row 1 (1-based) = screen row 0 = first content row (contentStartRow=0)
        // Mouse col 5 (1-based) = screen col 4
        handleMouse(
            MouseEvent(button: .left, row: 1, col: 5, kind: .press),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(sut.state.cursorRow == 0, "First content row should map to line 0")
        #expect(sut.state.mode == .editor)
    }

    @Test
    func `tree click converts 1-based mouse coordinates correctly`() {
        let sut = makeSUT(columns: 40, rows: 10)
        sut.state.treePanelWidth = 10
        sut.state.mode = .tree
        sut.state.treeNodes = (0..<5).map { i in
            FileNode(name: "file\(i).txt", path: "/file\(i).txt", isDirectory: false)
        }
        sut.state.cachedFlatTree = FileTreeNavigator.flatten(sut.state.treeNodes)

        // Mouse row 1 (1-based) = screen row 0 = contentStartRow
        // contentRow = mouse.row - 1 - contentStartRow = 1 - 1 - 0 = 0
        handleMouse(
            MouseEvent(button: .left, row: 1, col: 3, kind: .press),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(
            sut.state.selectedTreeIndex == 0, "First content row click should select tree index 0")
    }

    @Test
    func `right click on tree opens context menu without opening file`() {
        let sut = makeSUT(columns: 40, rows: 10)
        sut.state.treePanelWidth = 10
        sut.state.mode = .tree
        sut.state.treeNodes = [
            FileNode(name: "note.txt", path: "/note.txt", isDirectory: false)
        ]
        sut.state.cachedFlatTree = FileTreeNavigator.flatten(sut.state.treeNodes)

        handleMouse(
            MouseEvent(button: .right, row: 1, col: 3, kind: .press),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(sut.state.contextMenu?.target == .treeNode(index: 0))
        #expect(
            sut.state.contextMenu?.items.map(\.title) == [
                "Open",
                "Open and Pin",
                "Rename…",
                "Duplicate…",
                "Move…",
                "Delete…",
                "Save Here…",
            ])
        #expect(sut.state.bufferManager.count == 0)
    }

    @Test
    func `editor context menu click activates selected action`() throws {
        let sut = makeSUT(columns: 40, rows: 10)
        sut.state.beginNewFile()
        sut.state.mode = .editor
        sut.state.sidebarCollapsed = true

        handleMouse(
            MouseEvent(button: .right, row: 2, col: 10, kind: .press),
            state: sut.state,
            pipeline: sut.pipeline
        )

        let click = try #require(
            (1...10).lazy.compactMap { row in
                (1...40).lazy.compactMap { col in
                    let mouse = MouseEvent(button: .left, row: row, col: col, kind: .press)
                    return contextMenuItemIndex(at: mouse, state: sut.state, columns: 40, rows: 10)
                        == 0 ? mouse : nil
                }.first
            }.first
        )

        handleMouse(
            click,
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(sut.state.contextMenu == nil)
        #expect(sut.state.prompt?.kind == .savePath)
        #expect(sut.state.contextHintText == "Enter Save  Esc Cancel")
    }
}

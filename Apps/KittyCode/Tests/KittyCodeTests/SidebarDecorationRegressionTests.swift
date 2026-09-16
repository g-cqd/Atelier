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
struct SidebarDecorationRegressionTests {
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
    func `editor gutter renders git line decorations`() {
        let sut = makeSUT(fileContent: ["hello"], columns: 40, rows: 10)
        sut.state.mode = .editor
        sut.state.sidebarCollapsed = true
        sut.state.bufferManager.open(
            filePath: "/note.txt", fileName: "note.txt", content: "hello", language: nil)
        sut.state.restoreStateFromActiveBuffer()
        sut.state.bufferManager.activeBuffer?.gitLineDecorations = GitLineDecorations(markers: [
            0: .added
        ])
        sut.state.gitLineDecorationProvider = TestGitProvider()

        renderShellLayout(pipeline: sut.pipeline, state: sut.state)

        #expect(sut.pipeline.buffer[0, 0].character == "+")
        #expect(sut.pipeline.buffer[0, 3].character == "1")
    }

    @Test
    func `tab ribbon renders git status indicators for open buffers`() {
        let cols = 40
        let sut = makeSUT(fileContent: ["x"], columns: cols, rows: 10, tabRibbon: .top)
        sut.state.bufferManager.open(
            filePath: "/note.txt", fileName: "note.txt", content: "x", language: nil)
        sut.state.restoreStateFromActiveBuffer()
        sut.state.fileStatusProvider = TestGitProvider(statuses: ["/note.txt": .modified])

        renderShellLayout(pipeline: sut.pipeline, state: sut.state)

        let mCol = (0 ..< cols).first { sut.pipeline.buffer[0, $0].character == "M" }
        #expect(mCol != nil, "Expected 'M' indicator in tab ribbon row")
        if let col = mCol {
            let cell = sut.pipeline.buffer[0, col]
            #expect(
                cell.style == sut.state.colorScheme.gitModified,
                "M indicator should use gitModified style")
        }
    }

    @Test
    func `open files panel renders git status indicators`() {
        let cols = 40
        let sut = makeSUT(columns: cols, rows: 10)
        sut.state.treePanelWidth = 16
        sut.state.activeSidebarPanel = .openDocuments
        sut.state.bufferManager.open(
            filePath: "/note.txt", fileName: "note.txt", content: "x", language: nil)
        sut.state.restoreStateFromActiveBuffer()
        sut.state.fileStatusProvider = TestGitProvider(statuses: ["/note.txt": .modified])

        renderShellLayout(pipeline: sut.pipeline, state: sut.state)

        let mCol = (0 ..< 16).first { sut.pipeline.buffer[0, $0].character == "M" }
        #expect(mCol != nil, "Expected 'M' indicator in open files panel")
        if let col = mCol {
            let cell = sut.pipeline.buffer[0, col]
            #expect(
                cell.style == sut.state.colorScheme.gitModified,
                "M indicator should use gitModified style")
        }
    }

    @Test
    func `scrolling the tree repaints the top visible row`() throws {
        let sut = makeSUT(columns: 40, rows: 10)
        sut.state.sidebarCollapsed = false
        sut.state.treePanelWidth = 18
        sut.state.treeNodes = (0 ..< 20)
            .map { i in
                FileNode(
                    name: String(format: "file%02d.txt", i), path: "/file\(i).txt", isDirectory: false)
            }
        sut.state.cachedFlatTree = FileTreeNavigator.flatten(sut.state.treeNodes)

        renderFrame(pipeline: sut.pipeline, state: sut.state)
        try sut.pipeline.flush()

        sut.state.treeScrollOffset = 1
        renderFrame(pipeline: sut.pipeline, state: sut.state)

        let layout = LayoutMetrics(
            state: sut.state, columns: sut.pipeline.columns, rows: sut.pipeline.rows)
        let topRow = layout.contentStartRow
        let treeStartCol = layout.activityBarWidth
        let treeEndCol = treeStartCol + layout.sidebarWidth

        let topRowHasDirtyTreeCell = (treeStartCol ..< treeEndCol)
            .contains { col in
                sut.pipeline.buffer.dirty.isDirty(topRow * sut.pipeline.columns + col)
            }

        #expect(topRowHasDirtyTreeCell, "Top visible tree row should be repainted after scrolling")
    }
}

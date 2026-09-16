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
struct TreeRefreshRegressionTests {
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
    func `tree refresh preserves scroll offset`() async {
        let sut = makeSUT(columns: 40, rows: 10)
        sut.state.treeScrollOffset = 5
        sut.state.selectedTreeIndex = 7
        sut.state.treeNodes = (0 ..< 20)
            .map { i in
                FileNode(name: "file\(i).txt", path: "/file\(i).txt", isDirectory: false)
            }
        sut.state.cachedFlatTree = FileTreeNavigator.flatten(sut.state.treeNodes)

        // Simulate a tree refresh — loadInitialTree rescans, but we can't do async I/O in tests
        // so test refreshFlatTree directly (which loadInitialTree calls)
        sut.state.refreshFlatTree()

        // Scroll offset should not be reset
        #expect(sut.state.treeScrollOffset == 5)
        #expect(sut.state.selectedTreeIndex == 7)
    }

    @Test
    func `tree refresh clamps scroll offset when tree shrinks`() {
        let sut = makeSUT(columns: 40, rows: 10)
        sut.state.treeScrollOffset = 15
        sut.state.selectedTreeIndex = 18
        // Start with 20 items
        sut.state.treeNodes = (0 ..< 20)
            .map { i in
                FileNode(name: "file\(i).txt", path: "/file\(i).txt", isDirectory: false)
            }
        sut.state.cachedFlatTree = FileTreeNavigator.flatten(sut.state.treeNodes)

        // Shrink to 10 items
        sut.state.treeNodes = (0 ..< 10)
            .map { i in
                FileNode(name: "file\(i).txt", path: "/file\(i).txt", isDirectory: false)
            }
        sut.state.refreshFlatTree()

        // Scroll and selection should be clamped, not reset to 0
        let maxIndex = sut.state.cachedFlatTree.count - 1
        #expect(sut.state.treeScrollOffset <= maxIndex)
        #expect(sut.state.selectedTreeIndex <= maxIndex)
    }
}

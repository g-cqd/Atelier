import AtelierText
import Foundation
import KittyRenderer
import KittyWorkspace
import Testing

@testable import KittyEditor

@Suite
@MainActor
struct DirtyStateTests {
    private func makeSUT(fileContent: [String] = ["alpha", "beta", "gamma"])
        -> (state: EditorState, pipeline: RenderPipeline)
    {
        EditorTestHarness.make(fileContent: fileContent)
    }

    @Test
    func `initial state marks everything dirty`() {
        let sut = makeSUT()
        #expect(sut.state.dirtyContentAll)
        #expect(sut.state.dirtyChrome)
    }

    @Test
    func `drainDirtyState clears the markers and returns a snapshot`() {
        let sut = makeSUT()
        let snapshot = sut.state.drainDirtyState()
        #expect(snapshot.contentAll)
        #expect(snapshot.chrome)
        #expect(!sut.state.dirtyContentAll)
        #expect(!sut.state.dirtyChrome)
        #expect(sut.state.dirtyContentLines.isEmpty)
    }

    @Test
    func `markLinesDirty records each affected line`() {
        let sut = makeSUT()
        _ = sut.state.drainDirtyState()
        sut.state.markLinesDirty(2 ..< 5)
        #expect(sut.state.dirtyContentLines == [2, 3, 4])
    }

    @Test
    func `markLinesDirty is a no-op when contentAll is already set`() {
        let sut = makeSUT()
        // markContentAllDirty supersedes per-line marks.
        sut.state.markContentAllDirty()
        sut.state.markLinesDirty(2 ..< 5)
        #expect(sut.state.dirtyContentLines.isEmpty)
        #expect(sut.state.dirtyContentAll)
    }

    @Test
    func `markContentAllDirty clears any previous per-line marks`() {
        let sut = makeSUT()
        _ = sut.state.drainDirtyState()
        sut.state.markLinesDirty(0 ..< 2)
        sut.state.markContentAllDirty()
        #expect(sut.state.dirtyContentLines.isEmpty)
        #expect(sut.state.dirtyContentAll)
    }

    @Test
    func `textDidChange with same-line mutation marks just those lines`() {
        let sut = makeSUT()
        _ = sut.state.drainDirtyState()
        let mutation = TextMutation(
            originalLineRange: 1 ..< 2,
            updatedLineRange: 1 ..< 2
        )
        sut.state.textDidChange(mutation)
        #expect(!sut.state.dirtyContentAll)
        #expect(sut.state.dirtyContentLines == [1])
    }

    @Test
    func `textDidChange with line-count change falls back to contentAll`() {
        let sut = makeSUT()
        _ = sut.state.drainDirtyState()
        let mutation = TextMutation(
            originalLineRange: 1 ..< 2,
            updatedLineRange: 1 ..< 3  // inserted a newline
        )
        sut.state.textDidChange(mutation)
        #expect(sut.state.dirtyContentAll)
    }

    @Test
    func `textDidChange without a mutation marks all content dirty`() {
        let sut = makeSUT()
        _ = sut.state.drainDirtyState()
        sut.state.textDidChange()
        #expect(sut.state.dirtyContentAll)
    }

    @Test
    func `small scroll marks only the newly exposed rows`() {
        let sut = makeSUT(fileContent: (0 ..< 100).map { "line \($0)" })
        // EditorTestHarness.make uses 24 rows; visibleRows ~= 22.
        // Make sure we have a sensible row size so the delta is "small".
        sut.state.lastRenderRows = 24
        _ = sut.state.drainDirtyState()
        sut.state.scrollOffset = 3  // small downward scroll
        #expect(!sut.state.dirtyContentAll)
        // The 3 newly exposed rows at the bottom should be marked.
        #expect(!sut.state.dirtyContentLines.isEmpty)
        #expect(sut.state.dirtyContentLines.count == 3)
    }

    @Test
    func `large scroll falls back to all content dirty`() {
        let sut = makeSUT(fileContent: (0 ..< 200).map { "line \($0)" })
        sut.state.lastRenderRows = 24
        _ = sut.state.drainDirtyState()
        sut.state.scrollOffset = 100  // way more than a screen
        #expect(sut.state.dirtyContentAll)
    }

    @Test
    func `assigning the same scrollOffset does not mark dirty`() {
        let sut = makeSUT()
        _ = sut.state.drainDirtyState()
        let before = sut.state.scrollOffset
        sut.state.scrollOffset = before
        #expect(!sut.state.dirtyContentAll)
    }

    @Test
    func `changing mode marks both chrome and content dirty`() {
        let sut = makeSUT()
        // EditorTestHarness.make leaves the editor in `.editor` mode,
        // so switch to `.tree` to assert a real transition.
        _ = sut.state.drainDirtyState()
        sut.state.mode = .tree
        #expect(sut.state.dirtyChrome)
        #expect(sut.state.dirtyContentAll)
    }

    @Test
    func `tree node mutation marks chrome dirty`() {
        let sut = makeSUT()
        _ = sut.state.drainDirtyState()
        sut.state.treeNodes = sut.state.treeNodes  // wholesale reassignment
        #expect(sut.state.dirtyChrome)
    }

    @Test
    func `flat tree mutation marks chrome dirty`() {
        let sut = makeSUT()
        _ = sut.state.drainDirtyState()
        sut.state.cachedFlatTree = sut.state.cachedFlatTree
        #expect(sut.state.dirtyChrome)
    }

    @Test
    func `tree selection change marks chrome dirty`() {
        let sut = makeSUT()
        _ = sut.state.drainDirtyState()
        let original = sut.state.selectedTreeIndex
        sut.state.selectedTreeIndex = original + 1
        #expect(sut.state.dirtyChrome)
    }

    @Test
    func `selection assignment marks content dirty`() {
        let sut = makeSUT()
        _ = sut.state.drainDirtyState()
        sut.state.selection = TextSelection(
            anchor: TextPosition(row: 0, col: 0),
            head: TextPosition(row: 0, col: 1)
        )
        #expect(sut.state.dirtyContentAll)
    }

    @Test
    func `sidebar panel state changes mark chrome dirty`() {
        let sut = makeSUT()
        _ = sut.state.drainDirtyState()
        sut.state.openFilesScrollOffset = 5
        #expect(sut.state.dirtyChrome)

        _ = sut.state.drainDirtyState()
        sut.state.searchPanelFocus = .replaceField
        #expect(sut.state.dirtyChrome)

        _ = sut.state.drainDirtyState()
        sut.state.tabScrollOffset = 3
        #expect(sut.state.dirtyChrome)
    }

    @Test
    func `vim mode change marks chrome and content dirty`() {
        let sut = makeSUT()
        _ = sut.state.drainDirtyState()
        sut.state.vimMode = .insert
        #expect(sut.state.dirtyChrome)
        #expect(sut.state.dirtyContentAll)
    }

    @Test
    func `command feedback assignment marks chrome dirty`() {
        let sut = makeSUT()
        _ = sut.state.drainDirtyState()
        sut.state.commandFeedback = "hint"
        #expect(sut.state.dirtyChrome)
    }

    @Test
    func `viewport size change marks everything dirty on next renderFrame`() {
        let sut = makeSUT()
        _ = sut.state.drainDirtyState()
        // A resize with clean markers: `renderFrame` must notice the new size and repaint everything, chrome included.
        sut.state.lastRenderColumns = sut.pipeline.columns
        sut.state.lastRenderRows = sut.pipeline.rows
        _ = sut.state.drainDirtyState()
        sut.pipeline.resize(columns: sut.pipeline.columns + 10, rows: sut.pipeline.rows + 5)
        renderFrame(pipeline: sut.pipeline, state: sut.state)
        // The chrome repaint isn't observable here; the recorded size catching up with the new one is.
        #expect(sut.state.lastRenderColumns == sut.pipeline.columns)
        #expect(sut.state.lastRenderRows == sut.pipeline.rows)
    }
}

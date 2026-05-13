import Foundation
import KittyRenderer
import KittyText
import Testing

@testable import KittyCode

@Suite
@MainActor
struct DirtyStateTests {
    private func makeSUT(fileContent: [String] = ["alpha", "beta", "gamma"])
        -> (state: EditorState, pipeline: RenderPipeline)
    {
        makeKittyCodeNavigationContext(fileContent: fileContent)
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
        sut.state.markLinesDirty(2..<5)
        #expect(sut.state.dirtyContentLines == [2, 3, 4])
    }

    @Test
    func `markLinesDirty is a no-op when contentAll is already set`() {
        let sut = makeSUT()
        // markContentAllDirty supersedes per-line marks.
        sut.state.markContentAllDirty()
        sut.state.markLinesDirty(2..<5)
        #expect(sut.state.dirtyContentLines.isEmpty)
        #expect(sut.state.dirtyContentAll)
    }

    @Test
    func `markContentAllDirty clears any previous per-line marks`() {
        let sut = makeSUT()
        _ = sut.state.drainDirtyState()
        sut.state.markLinesDirty(0..<2)
        sut.state.markContentAllDirty()
        #expect(sut.state.dirtyContentLines.isEmpty)
        #expect(sut.state.dirtyContentAll)
    }

    @Test
    func `textDidChange with same-line mutation marks just those lines`() {
        let sut = makeSUT()
        _ = sut.state.drainDirtyState()
        let mutation = TextMutation(
            originalLineRange: 1..<2,
            updatedLineRange: 1..<2
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
            originalLineRange: 1..<2,
            updatedLineRange: 1..<3  // inserted a newline
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
    func `changing scrollOffset marks all content dirty`() {
        let sut = makeSUT(fileContent: (0..<20).map { "line \($0)" })
        _ = sut.state.drainDirtyState()
        sut.state.scrollOffset = 5
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
        // makeKittyCodeNavigationContext leaves the editor in `.editor` mode,
        // so switch to `.tree` to assert a real transition.
        _ = sut.state.drainDirtyState()
        sut.state.mode = .tree
        #expect(sut.state.dirtyChrome)
        #expect(sut.state.dirtyContentAll)
    }
}

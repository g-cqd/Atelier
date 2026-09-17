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
struct ScrollRenderingContentTests {
    private func makeSUT(
        lineCount: Int = 100,
        columns: Int = 40,
        rows: Int = 12
    ) -> (state: EditorState, pipeline: RenderPipeline) {
        EditorTestHarness.makeScrollRendering(lineCount: lineCount, columns: columns, rows: rows)
    }

    @Test
    func `scroll down renders correct content without clearing`() throws {
        let sut = makeSUT()
        // Initial render at scrollOffset 0
        renderFrame(pipeline: sut.pipeline, state: sut.state)
        try sut.pipeline.flush()

        // Scroll down by 3
        sut.state.scrollOffset = 3
        renderFrame(pipeline: sut.pipeline, state: sut.state)

        // Content area starts at row 0 (no title bar).
        // The first visible line should now be "line 3 ..."
        let contentRow = 0
        let rowChars = (0 ..< 40).map { sut.pipeline.buffer[contentRow, $0].character }
        let rowText = String(rowChars)
        #expect(
            rowText.contains("line 3"),
            "First editor row should show line 3 after scrolling down, got: \(rowText)")
    }

    @Test
    func `scroll up renders correct content without clearing`() throws {
        let sut = makeSUT()
        // Start at scrollOffset 10
        sut.state.scrollOffset = 10
        renderFrame(pipeline: sut.pipeline, state: sut.state)
        try sut.pipeline.flush()

        // Scroll up by 3
        sut.state.scrollOffset = 7
        renderFrame(pipeline: sut.pipeline, state: sut.state)

        let contentRow = 0
        let rowChars = (0 ..< 40).map { sut.pipeline.buffer[contentRow, $0].character }
        let rowText = String(rowChars)
        #expect(
            rowText.contains("line 7"),
            "First editor row should show line 7 after scrolling up, got: \(rowText)")
    }

    @Test
    func `large scroll jump still renders correctly`() throws {
        let sut = makeSUT()
        renderFrame(pipeline: sut.pipeline, state: sut.state)
        try sut.pipeline.flush()

        // Jump by more than viewport height — pre-shift is skipped
        sut.state.scrollOffset = 50
        renderFrame(pipeline: sut.pipeline, state: sut.state)

        let contentRow = 0
        let rowChars = (0 ..< 40).map { sut.pipeline.buffer[contentRow, $0].character }
        let rowText = String(rowChars)
        #expect(
            rowText.contains("line 50"),
            "First editor row should show line 50 after large jump, got: \(rowText)")
    }

    @Test
    func `multiple consecutive scrolls produce correct content`() throws {
        let sut = makeSUT()
        renderFrame(pipeline: sut.pipeline, state: sut.state)
        try sut.pipeline.flush()

        // Scroll down 5 times by 1
        for i in 1 ... 5 {
            sut.state.scrollOffset = i
            renderFrame(pipeline: sut.pipeline, state: sut.state)
            try sut.pipeline.flush()
        }

        let contentRow = 0
        let rowChars = (0 ..< 40).map { sut.pipeline.buffer[contentRow, $0].character }
        let rowText = String(rowChars)
        #expect(
            rowText.contains("line 5"),
            "After 5 scroll-down steps, first row should show line 5, got: \(rowText)")
    }

    @Test
    func `scroll down then up returns to original content`() throws {
        let sut = makeSUT()
        renderFrame(pipeline: sut.pipeline, state: sut.state)
        try sut.pipeline.flush()

        // Scroll down
        sut.state.scrollOffset = 5
        renderFrame(pipeline: sut.pipeline, state: sut.state)
        try sut.pipeline.flush()

        // Scroll back up
        sut.state.scrollOffset = 0
        renderFrame(pipeline: sut.pipeline, state: sut.state)

        let contentRow = 0
        let rowChars = (0 ..< 40).map { sut.pipeline.buffer[contentRow, $0].character }
        let rowText = String(rowChars)
        #expect(
            rowText.contains("line 0"),
            "After scroll down+up, first row should show line 0, got: \(rowText)")
    }
}

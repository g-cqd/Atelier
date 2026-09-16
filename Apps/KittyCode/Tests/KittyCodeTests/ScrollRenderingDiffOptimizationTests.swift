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
struct ScrollRenderingDiffOptimizationTests {
    private func makeSUT(
        lineCount: Int = 100,
        columns: Int = 40,
        rows: Int = 12
    ) -> (state: EditorState, pipeline: RenderPipeline) {
        makeScrollRenderingContext(lineCount: lineCount, columns: columns, rows: rows)
    }

    @Test
    func `pre-shift reduces dirty cells on scroll down`() throws {
        let sut = makeSUT()
        renderFrame(pipeline: sut.pipeline, state: sut.state)
        try sut.pipeline.flush()

        // Scroll down by 1
        sut.state.scrollOffset = 1
        renderFrame(pipeline: sut.pipeline, state: sut.state)

        // Count dirty cells in the content area (rows 0..<12, all columns)
        let cols = 40
        var dirtyCount = 0
        for row in 0 ..< 12 {
            for col in 0 ..< cols where sut.pipeline.buffer.dirty.isDirty(row * cols + col) {
                dirtyCount += 1
            }
        }

        // Without pre-shift, all ~440 content cells would be dirty.
        // With pre-shift, only the new bottom row + line number changes should be dirty.
        // Line numbers change by 1 digit on every row, so expect roughly:
        //   1 full row (new content) + small gutter changes ≈ < 220 cells
        let totalContentCells = 11 * cols
        #expect(
            dirtyCount < totalContentCells,
            "Dirty cells (\(dirtyCount)) should be less than total content cells (\(totalContentCells))"
        )
    }

    @Test
    func `pre-shift reduces dirty cells on scroll up`() throws {
        let sut = makeSUT()
        sut.state.scrollOffset = 10
        renderFrame(pipeline: sut.pipeline, state: sut.state)
        try sut.pipeline.flush()

        // Scroll up by 1
        sut.state.scrollOffset = 9
        renderFrame(pipeline: sut.pipeline, state: sut.state)

        let cols = 40
        var dirtyCount = 0
        for row in 0 ..< 12 {
            for col in 0 ..< cols where sut.pipeline.buffer.dirty.isDirty(row * cols + col) {
                dirtyCount += 1
            }
        }

        let totalContentCells = 11 * cols
        #expect(
            dirtyCount < totalContentCells,
            "Dirty cells (\(dirtyCount)) should be less than total content cells (\(totalContentCells))"
        )
    }

    @Test
    func `flush output is smaller for scrolled frame than initial frame`() throws {
        let mock = MockTerminalConnection(size: TerminalSize(columns: 40, rows: 12))
        let pipeline = RenderPipeline(connection: mock, columns: 40, rows: 12)

        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbon.position = .hidden
        config.statusBar.show = false
        let state = EditorState(rootPath: ".", config: config)
        state.sidebarCollapsed = true
        state.mode = .editor
        state.fileContent = (0 ..< 100).map { "line \($0) content here" }
        state.refreshHighlights()

        // Initial render
        renderFrame(pipeline: pipeline, state: state)
        try pipeline.flush()
        let initialSize = mock.writtenOutput.count
        mock.clearOutput()

        // Scroll by 1 and re-render
        state.scrollOffset = 1
        renderFrame(pipeline: pipeline, state: state)
        try pipeline.flush()
        let scrolledSize = mock.writtenOutput.count

        #expect(
            scrolledSize < initialSize,
            "Scrolled flush (\(scrolledSize) bytes) should be smaller than initial flush (\(initialSize) bytes)"
        )
    }
}

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
struct MouseScrollNavigationTests {

    private func makeSUT(fileContent: [String], columns: Int = 80, rows: Int = 24) -> (
        state: EditorState, pipeline: RenderPipeline
    ) {
        makeKittyCodeNavigationContext(fileContent: fileContent, columns: columns, rows: rows)
    }

    @Test
    func `horizontal mouse wheel events update horizontal scroll offset`() {
        let sut = makeSUT(
            fileContent: ["0123456789abcdefghijklmnopqrstuvwxyz"], columns: 18, rows: 8)
        sut.state.mode = .editor
        sut.state.sidebarCollapsed = true

        handleMouse(
            MouseEvent(button: .scrollRight, row: 2, col: 5, kind: .press),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(sut.state.hScrollOffset == 4)
    }

    @Test
    func `reversing scroll direction keeps accepting the new direction`() {
        let sut = makeSUT(fileContent: (0..<200).map(String.init), rows: 12)
        sut.state.config.editor.scrollLines = 1
        sut.state.config.editor.scrollAccelerationEnabled = false
        sut.state.scrollOffset = 30
        sut.state.sidebarCollapsed = true

        handleMouse(
            MouseEvent(button: .scrollDown, row: 2, col: 40, kind: .press),
            state: sut.state,
            pipeline: sut.pipeline
        )
        handleMouse(
            MouseEvent(button: .scrollUp, row: 2, col: 40, kind: .press),
            state: sut.state,
            pipeline: sut.pipeline
        )
        handleMouse(
            MouseEvent(button: .scrollUp, row: 2, col: 40, kind: .press),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(sut.state.scrollOffset == 29)
    }

    @Test
    func `stale rebound event is ignored once after a reversal`() {
        let sut = makeSUT(fileContent: (0..<200).map(String.init), rows: 12)
        sut.state.config.editor.scrollLines = 1
        sut.state.config.editor.scrollAccelerationEnabled = false
        sut.state.scrollOffset = 30
        sut.state.sidebarCollapsed = true

        handleMouse(
            MouseEvent(button: .scrollDown, row: 2, col: 40, kind: .press),
            state: sut.state,
            pipeline: sut.pipeline
        )
        handleMouse(
            MouseEvent(button: .scrollUp, row: 2, col: 40, kind: .press),
            state: sut.state,
            pipeline: sut.pipeline
        )
        handleMouse(
            MouseEvent(button: .scrollDown, row: 2, col: 40, kind: .press),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(sut.state.scrollOffset == 30)
    }

    @Test
    func `rapid same-direction scroll bursts enqueue extra line-by-line steps`() {
        let sut = makeSUT(fileContent: (0..<200).map(String.init), rows: 12)
        sut.state.sidebarCollapsed = true
        sut.state.config.editor.scrollLines = 1
        sut.state.config.editor.scrollAccelerationEnabled = true
        sut.state.config.editor.scrollAccelerationWindowMilliseconds = 100
        sut.state.config.editor.scrollAccelerationStepIntervalMilliseconds = 5
        sut.state.config.editor.scrollAccelerationMaxExtraLines = 2

        handleMouse(
            MouseEvent(button: .scrollDown, row: 2, col: 40, kind: .press),
            state: sut.state,
            pipeline: sut.pipeline
        )
        handleMouse(
            MouseEvent(button: .scrollDown, row: 2, col: 40, kind: .press),
            state: sut.state,
            pipeline: sut.pipeline
        )
        handleMouse(
            MouseEvent(button: .scrollDown, row: 2, col: 40, kind: .press),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(sut.state.scrollOffset == 3)

        settlePendingAcceleratedScroll(sut.state)

        #expect(sut.state.scrollOffset == 7)
    }

    @Test
    func `opposing direction cancels pending accelerated scroll immediately`() {
        let sut = makeSUT(fileContent: (0..<200).map(String.init), rows: 12)
        sut.state.sidebarCollapsed = true
        sut.state.config.editor.scrollLines = 1
        sut.state.config.editor.scrollAccelerationEnabled = true
        sut.state.config.editor.scrollAccelerationWindowMilliseconds = 100
        sut.state.config.editor.scrollAccelerationStepIntervalMilliseconds = 200
        sut.state.config.editor.scrollAccelerationMaxExtraLines = 2

        handleMouse(
            MouseEvent(button: .scrollDown, row: 2, col: 40, kind: .press),
            state: sut.state,
            pipeline: sut.pipeline
        )
        handleMouse(
            MouseEvent(button: .scrollDown, row: 2, col: 40, kind: .press),
            state: sut.state,
            pipeline: sut.pipeline
        )
        handleMouse(
            MouseEvent(button: .scrollDown, row: 2, col: 40, kind: .press),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(sut.state.scrollOffset == 3)
        #expect(sut.state.pendingAcceleratedScrollLines == 4)

        handleMouse(
            MouseEvent(button: .scrollUp, row: 2, col: 40, kind: .press),
            state: sut.state,
            pipeline: sut.pipeline
        )

        settlePendingAcceleratedScroll(sut.state)

        #expect(sut.state.scrollOffset == 2)
        #expect(sut.state.pendingAcceleratedScrollLines == 0)
    }

    @Test
    func `scrolling past vertical limits cancels immediately`() {
        let top = makeSUT(fileContent: (0..<5).map(String.init), rows: 12)
        top.state.sidebarCollapsed = true
        top.state.config.editor.scrollLines = 1
        top.state.config.editor.scrollAccelerationEnabled = true
        top.state.config.editor.scrollAccelerationWindowMilliseconds = 100
        top.state.config.editor.scrollAccelerationStepIntervalMilliseconds = 200
        top.state.config.editor.scrollAccelerationMaxExtraLines = 2

        handleMouse(
            MouseEvent(button: .scrollUp, row: 2, col: 40, kind: .press),
            state: top.state,
            pipeline: top.pipeline
        )
        handleMouse(
            MouseEvent(button: .scrollUp, row: 2, col: 40, kind: .press),
            state: top.state,
            pipeline: top.pipeline
        )

        #expect(top.state.scrollOffset == 0)
        #expect(top.state.pendingAcceleratedScrollLines == 0)
        #expect(top.state.scrollAccelerationTask == nil)
        #expect(top.state.lastScrollDirection == nil)
        #expect(top.state.isScrolling == false)

        let bottom = makeSUT(fileContent: (0..<5).map(String.init), rows: 12)
        bottom.state.sidebarCollapsed = true
        bottom.state.config.editor.scrollLines = 1
        bottom.state.config.editor.scrollAccelerationEnabled = true
        bottom.state.config.editor.scrollAccelerationWindowMilliseconds = 100
        bottom.state.config.editor.scrollAccelerationStepIntervalMilliseconds = 200
        bottom.state.config.editor.scrollAccelerationMaxExtraLines = 2
        bottom.state.scrollOffset = bottom.state.fileLineCount - 2

        handleMouse(
            MouseEvent(button: .scrollDown, row: 2, col: 40, kind: .press),
            state: bottom.state,
            pipeline: bottom.pipeline
        )
        handleMouse(
            MouseEvent(button: .scrollDown, row: 2, col: 40, kind: .press),
            state: bottom.state,
            pipeline: bottom.pipeline
        )
        handleMouse(
            MouseEvent(button: .scrollDown, row: 2, col: 40, kind: .press),
            state: bottom.state,
            pipeline: bottom.pipeline
        )

        #expect(bottom.state.scrollOffset == bottom.state.fileLineCount - 1)
        #expect(bottom.state.pendingAcceleratedScrollLines == 0)
        #expect(bottom.state.scrollAccelerationTask == nil)
        #expect(bottom.state.isScrolling == false)
    }

    @Test
    func `scrolling past horizontal limits cancels immediately`() {
        let sut = makeSUT(
            fileContent: ["0123456789abcdefghijklmnopqrstuvwxyz"], columns: 18, rows: 8)
        sut.state.mode = .editor
        sut.state.sidebarCollapsed = true
        sut.state.config.editor.wrapLines = false

        let layout = LayoutMetrics(
            state: sut.state, columns: sut.pipeline.columns, rows: sut.pipeline.rows)
        let editorRect = Rect(
            x: layout.editorStart,
            y: layout.contentStartRow,
            width: layout.editorWidth,
            height: layout.contentRows
        )
        let metrics = TextEditorLayout.horizontalScrollMetrics(
            for: makeEditorView(state: sut.state),
            in: editorRect,
            maxLineWidth: sut.state.maxLineWidth
        )

        sut.state.hScrollOffset = 0
        handleMouse(
            MouseEvent(button: .scrollLeft, row: 2, col: 5, kind: .press),
            state: sut.state,
            pipeline: sut.pipeline
        )
        #expect(sut.state.hScrollOffset == 0)
        #expect(sut.state.isScrolling == false)

        sut.state.hScrollOffset = metrics.maxOffset
        handleMouse(
            MouseEvent(button: .scrollRight, row: 2, col: 5, kind: .press),
            state: sut.state,
            pipeline: sut.pipeline
        )
        #expect(sut.state.hScrollOffset == metrics.maxOffset)
        #expect(sut.state.isScrolling == false)
    }
}

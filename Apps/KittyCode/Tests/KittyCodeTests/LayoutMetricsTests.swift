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
struct LayoutMetricsTests {
    @Test
    func `editorStart with sidebar visible`() {
        var config = KittyConfig()
        config.activityBar.show = true
        let state = EditorState(rootPath: ".", config: config)
        state.treePanelWidth = 20
        state.sidebarCollapsed = false

        let layout = LayoutMetrics(state: state, columns: 80, rows: 24)
        // activityBarWidth(3) + sidebarWidth(20) + separator(1) = 24
        #expect(layout.editorStart == 24)
        #expect(layout.editorWidth == 56)
        #expect(layout.activityBarWidth == 3)
        #expect(layout.sidebarWidth == 20)
    }

    @Test
    func `editorStart with sidebar collapsed`() {
        var config = KittyConfig()
        config.activityBar.show = true
        let state = EditorState(rootPath: ".", config: config)
        state.sidebarCollapsed = true

        let layout = LayoutMetrics(state: state, columns: 80, rows: 24)
        #expect(layout.editorStart == 0)
        #expect(layout.editorWidth == 80)
        #expect(layout.activityBarWidth == 0)
        #expect(layout.sidebarWidth == 0)
    }

    @Test
    func `contentRows accounts for tab ribbon`() {
        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbon.position = .top
        let state = EditorState(rootPath: ".", config: config)
        state.sidebarCollapsed = true
        // Need at least one buffer for tab ribbon to show
        state.bufferManager.open(filePath: "/a.txt", fileName: "a.txt", content: "", language: nil)

        let layout = LayoutMetrics(state: state, columns: 80, rows: 24)
        #expect(layout.showTabRibbon == true)
        #expect(layout.contentStartRow == 1)
        #expect(layout.contentRows == 22)  // rows - 1 - tabRows = 24 - 1 - 1 = 22
    }

    @Test
    func `static editorStart matches instance editorStart`() {
        var config = KittyConfig()
        config.activityBar.show = true
        let state = EditorState(rootPath: ".", config: config)
        state.treePanelWidth = 15
        state.sidebarCollapsed = false

        let layout = LayoutMetrics(state: state, columns: 60, rows: 20)
        let staticStart = LayoutMetrics.editorStart(state: state, columns: 60)
        #expect(layout.editorStart == staticStart)
    }

    @Test
    func `sidebarWidth is clamped to half of columns`() {
        var config = KittyConfig()
        config.activityBar.show = false
        let state = EditorState(rootPath: ".", config: config)
        state.treePanelWidth = 100
        state.sidebarCollapsed = false

        let layout = LayoutMetrics(state: state, columns: 40, rows: 24)
        #expect(layout.sidebarWidth == 20)
    }
}

/// With pixel chrome the separator is a placement under the editor's first column, not a column of its own.
@Suite
@MainActor
struct PixelChromeLayoutTests {
    @Test
    func `pixel chrome gives the separator column back to the editor`() {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        state.treePanelWidth = 20
        state.sidebarCollapsed = false

        let cellChrome = LayoutMetrics(state: state, columns: 80, rows: 24)
        state.usesPixelChrome = true
        let pixelChrome = LayoutMetrics(state: state, columns: 80, rows: 24)

        #expect(cellChrome.editorStart == pixelChrome.editorStart + 1)
        #expect(pixelChrome.editorWidth == cellChrome.editorWidth + 1)
        #expect(LayoutMetrics.editorStart(state: state, columns: 80) == pixelChrome.editorStart)
    }

    @Test
    func `the shell draws the separator as a pixel line instead of glyphs when the pipeline has chrome`() {
        let sut = EditorTestHarness.make(fileContent: ["a"], columns: 60, rows: 10, tabRibbon: .top)
        sut.state.treePanelWidth = 20
        sut.state.bufferManager.open(filePath: "/a.txt", fileName: "a.txt", content: "a", language: nil)
        sut.state.restoreStateFromActiveBuffer()
        renderShellLayout(pipeline: sut.pipeline, state: sut.state)
        #expect(sut.pipeline.chromeLines.isEmpty)
        #expect(sut.pipeline.buffer[1, 20].character == "\u{2502}")

        sut.pipeline.chrome = PixelChrome(cell: .init(width: 8, height: 16))
        sut.pipeline.beginFrame()
        renderShellLayout(pipeline: sut.pipeline, state: sut.state)
        let separator = ColorRGB(sut.state.colorScheme.separator.fg)
        #expect(
            sut.pipeline.chromeLines == [
                ChromeLine(axis: .vertical, row: 1, column: 20, length: 8, color: separator!),
                ChromeLine(axis: .horizontal, row: 1, column: 20, length: 40, color: separator!),
                ChromeLine(axis: .horizontal, row: 9, column: 0, length: 60, color: separator!)
            ])
        #expect(sut.pipeline.buffer[1, 20].character != "\u{2502}")
        #expect(sut.state.usesPixelChrome)
    }

    @Test
    func `the editor's selection, current line, search hits and scroll thumb become pixel fills and bars`() {
        var lines = (0 ..< 200).map { "line \($0) text" }
        lines[5] = "\tselected words here"
        let sut = EditorTestHarness.make(fileContent: lines, columns: 80, rows: 12, sidebarCollapsed: true)
        sut.state.bufferManager.open(
            filePath: "/big.txt", fileName: "big.txt", content: lines.joined(separator: "\n"), language: nil)
        sut.state.restoreStateFromActiveBuffer()
        sut.state.config.editor.highlightCurrentLine = true
        sut.state.colorScheme = EditorState.makeColorScheme(config: sut.state.config)
        sut.state.mode = .editor
        sut.state.cursorRow = 5
        sut.state.cursorCol = 3
        sut.state.selection = TextSelection(anchor: TextPosition(row: 5, col: 1), head: TextPosition(row: 6, col: 4))
        sut.pipeline.chrome = PixelChrome(cell: .init(width: 10, height: 20))
        sut.pipeline.beginFrame()
        renderShellLayout(pipeline: sut.pipeline, state: sut.state)

        let fills = sut.pipeline.chromeElements.compactMap { element -> (row: Int, column: Int, columns: Int)? in
            if case .fill(let row, let column, let columns, _, _) = element { return (row, column, columns) }
            return nil
        }
        let gutter = 4  // three digits of line numbers plus a space
        // Row 5 is the cursor line (full band) and the selection's first row from the tab's display width on.
        #expect(fills.contains { $0.row == 5 && $0.column == gutter })
        #expect(fills.contains { $0.row == 5 && $0.column == gutter + 4 })
        #expect(fills.contains { $0.row == 6 && $0.column == gutter && $0.columns == 4 })
        let bars = sut.pipeline.chromeElements.filter {
            guard case .bar = $0 else { return false }
            return true
        }
        #expect(bars.count == 2)
        // The cells no longer carry the selection background.
        #expect(sut.pipeline.buffer[5, gutter + 4].style.bg == .default)
        #expect(sut.pipeline.buffer[5, gutter + 4].character == "s")
    }
}

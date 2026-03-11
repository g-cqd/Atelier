import Foundation
import KittyCodecs
import KittyGit
import KittyFileTree
import KittyRenderer
import KittySyntax
import KittyTerminal
import KittyText
import KittyWidgets
import KittyWorkspace
import Testing
@testable import KittyCode

@Suite
struct KittyCodeConfigTests {
    @Test
    func `ColorRGB parses hex string`() {
        let parsed = ColorRGB(hex: "#1e2f3a")
        #expect(parsed != nil)
        #expect(parsed?.r == 0x1e)
        #expect(parsed?.g == 0x2f)
        #expect(parsed?.b == 0x3a)
    }

    @Test
    func `ColorRGB codable supports hex string`() throws {
        let json = "\"#abcdef\""
        let data = Data(json.utf8)
        let color = try JSONDecoder().decode(ColorRGB.self, from: data)
        #expect(color == ColorRGB(r: 0xab, g: 0xcd, b: 0xef))
    }

    @Test
    func `ColorRGB rejects invalid hex`() {
        #expect(ColorRGB(hex: "#zzz999") == nil)
        #expect(ColorRGB(hex: "#12345") == nil)
        #expect(ColorRGB(hex: "#1234567") == nil)
    }

    @Test
    func `ColorRGB parses 8 digit hex with alpha`() {
        let parsed = ColorRGB(hex: "#FF000080")
        #expect(parsed != nil)
        #expect(parsed?.r == 0xFF)
        #expect(parsed?.g == 0x00)
        #expect(parsed?.b == 0x00)
        #expect(parsed?.alpha == Double(0x80) / 255.0)
    }

    @Test
    func `ColorRGB 8 digit hex FF alpha is 1`() {
        let parsed = ColorRGB(hex: "#ABCDEFFF")
        #expect(parsed != nil)
        #expect(parsed?.r == 0xAB)
        #expect(parsed?.g == 0xCD)
        #expect(parsed?.b == 0xEF)
        #expect(parsed?.alpha == 1.0)
    }

    @Test
    func `ColorRGB 8 digit hex 00 alpha is 0`() {
        let parsed = ColorRGB(hex: "#ABCDEF00")
        #expect(parsed != nil)
        #expect(parsed?.alpha == 0.0)
    }

    @Test
    func `ColorRGB encodes 8 digit hex when alpha below 1`() throws {
        let color = ColorRGB(r: 0xFF, g: 0x00, b: 0x00, alpha: 0.5)
        let data = try JSONEncoder().encode(color)
        let hex = String(data: data, encoding: .utf8)!
        #expect(hex.contains("ff000080"))
    }

    @Test
    func `ColorRGB encodes 6 digit hex when alpha is 1`() throws {
        let color = ColorRGB(r: 0xAB, g: 0xCD, b: 0xEF)
        let data = try JSONEncoder().encode(color)
        let hex = String(data: data, encoding: .utf8)!
        #expect(hex.contains("abcdef"))
        #expect(!hex.contains("abcdefff"))
    }

    @Test
    func `ColorRGB codable roundtrips alpha`() throws {
        let original = ColorRGB(r: 0x11, g: 0x22, b: 0x33, alpha: 0.5)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ColorRGB.self, from: data)
        #expect(decoded.r == original.r)
        #expect(decoded.g == original.g)
        #expect(decoded.b == original.b)
        #expect(abs(decoded.alpha - original.alpha) < 0.01)
    }

    @Test
    func `ColorRGB HSB init produces correct red`() {
        let red = ColorRGB(hue: 0, saturation: 1, brightness: 1)
        #expect(red.r == 255)
        #expect(red.g == 0)
        #expect(red.b == 0)
        #expect(red.alpha == 1)
    }

    @Test
    func `ColorRGB HSB init produces correct green`() {
        let green = ColorRGB(hue: 1.0 / 3.0, saturation: 1, brightness: 1)
        #expect(green.r == 0)
        #expect(green.g == 255)
        #expect(green.b == 0)
    }

    @Test
    func `ColorRGB HSB init with alpha`() {
        let color = ColorRGB(hue: 0, saturation: 1, brightness: 1, alpha: 0.5)
        #expect(color.r == 255)
        #expect(color.alpha == 0.5)
    }

    @Test
    func `ColorRGB OKLCH init produces plausible values`() {
        let color = ColorRGB(lightness: 0.7, chroma: 0.15, hue: 150)
        #expect(color.g > color.r)
        #expect(color.alpha == 1)
    }

    @Test
    func `ColorRGB OKLCH init with alpha`() {
        let color = ColorRGB(lightness: 0.5, chroma: 0.1, hue: 30, alpha: 0.3)
        #expect(color.alpha == 0.3)
    }

    @Test
    func `ColorRGB OKLCH white`() {
        let white = ColorRGB(lightness: 1, chroma: 0, hue: 0)
        #expect(white.r == 255)
        #expect(white.g == 255)
        #expect(white.b == 255)
    }

    @Test
    func `ColorRGB OKLCH black`() {
        let black = ColorRGB(lightness: 0, chroma: 0, hue: 0)
        #expect(black.r == 0)
        #expect(black.g == 0)
        #expect(black.b == 0)
    }

    @Test
    func `Color overlay config decodes shorthand and alpha object`() throws {
        let shorthand = try JSONDecoder().decode(
            ColorOverlayConfig.self,
            from: Data("\"#abcdef\"".utf8)
        )
        let alphaOverlay = try JSONDecoder().decode(
            ColorOverlayConfig.self,
            from: Data("{\"color\":\"#112233\",\"alpha\":0.25}".utf8)
        )

        #expect(shorthand.color == ColorRGB(r: 0xab, g: 0xcd, b: 0xef))
        #expect(shorthand.alpha == 1)
        #expect(alphaOverlay.color == ColorRGB(r: 0x11, g: 0x22, b: 0x33))
        #expect(alphaOverlay.alpha == 0.25)
    }

    @Test
    func `Color overlay config decodes 8 digit hex shorthand`() throws {
        let overlay = try JSONDecoder().decode(
            ColorOverlayConfig.self,
            from: Data("\"#FF000080\"".utf8)
        )
        #expect(overlay.color == ColorRGB(r: 0xFF, g: 0x00, b: 0x00))
        #expect(abs(overlay.alpha - Double(0x80) / 255.0) < 0.01)
    }

    @Test
    @MainActor
    func `Color scheme uses terminal default backgrounds`() {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        #expect(state.colorScheme.editorText.bg == .default)
        #expect(state.colorScheme.treeBg.bg == .default)
        #expect(state.colorScheme.statusBar.bg == .default)
    }
}

@Suite
@MainActor
struct KittyCodeNavigationTests {
    private func makeSUT(fileContent: [String], columns: Int = 80, rows: Int = 24) -> (state: EditorState, pipeline: RenderPipeline) {
        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbon.position = .hidden
        let state = EditorState(rootPath: ".", config: config)
        state.mode = .editor
        state.fileContent = fileContent

        let pipeline = RenderPipeline(
            connection: MockTerminalConnection(size: TerminalSize(columns: columns, rows: rows)),
            columns: columns,
            rows: rows
        )

        return (state, pipeline)
    }

    private func waitForPendingScrollAccelerationToSettle(_ state: EditorState) async {
        let deadline = Date().addingTimeInterval(1)
        while (state.pendingAcceleratedScrollLines != 0 || state.scrollAccelerationTask != nil),
              Date() < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }

        if state.pendingAcceleratedScrollLines != 0 || state.scrollAccelerationTask != nil {
            Issue.record("Timed out waiting for pending accelerated scroll to settle")
        }
    }

    @Test
    func `Word jump forward moves to next token`() {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        state.fileContent = ["alpha   beta"]
        state.cursorRow = 0
        state.cursorCol = 0

        jumpWordForward(state: state)
        #expect(state.cursorCol == 8)
    }

    @Test
    func `Word jump backward moves to previous token start`() {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        state.fileContent = ["alpha   beta"]
        state.cursorRow = 0
        state.cursorCol = 12

        jumpWordBackward(state: state)
        #expect(state.cursorCol == 8)
    }

    @Test
    func `ensureEditorVisible updates horizontal scroll`() {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        state.fileContent = ["0123456789abcdefghijklmnopqrstuvwxyz"]
        state.cursorRow = 0
        state.cursorCol = 25
        state.hScrollOffset = 0
        state.config.editor.wrapLines = false

        ensureEditorVisible(state, contentRows: 10, availWidth: 8)
        #expect(state.hScrollOffset > 0)
        #expect(state.hScrollOffset == 18)
    }

    @Test
    func `horizontal mouse wheel events update horizontal scroll offset`() {
        let sut = makeSUT(fileContent: ["0123456789abcdefghijklmnopqrstuvwxyz"], columns: 18, rows: 8)
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
    func `rapid same-direction scroll bursts enqueue extra line-by-line steps`() async {
        let sut = makeSUT(fileContent: (0..<200).map(String.init), rows: 12)
        sut.state.sidebarCollapsed = true
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

        await waitForPendingScrollAccelerationToSettle(sut.state)

        #expect(sut.state.scrollOffset == 7)
    }

    @Test
    func `opposing direction cancels pending accelerated scroll immediately`() async {
        let sut = makeSUT(fileContent: (0..<200).map(String.init), rows: 12)
        sut.state.sidebarCollapsed = true
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

        await waitForPendingScrollAccelerationToSettle(sut.state)

        #expect(sut.state.scrollOffset == 2)
        #expect(sut.state.pendingAcceleratedScrollLines == 0)
    }

    @Test
    func `scrolling past vertical limits cancels immediately`() {
        let top = makeSUT(fileContent: (0..<5).map(String.init), rows: 12)
        top.state.sidebarCollapsed = true
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
        let sut = makeSUT(fileContent: ["0123456789abcdefghijklmnopqrstuvwxyz"], columns: 18, rows: 8)
        sut.state.mode = .editor
        sut.state.sidebarCollapsed = true
        sut.state.config.editor.wrapLines = false

        let layout = LayoutMetrics(state: sut.state, columns: sut.pipeline.columns, rows: sut.pipeline.rows)
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

    @Test
    func `ensureTreeVisible scrolls selected row into viewport`() {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        // Populate the underlying FileNode tree and flatten it
        state.treeNodes = (0..<40).map { i in
            FileNode(name: "f\(i)", path: "p\(i)", isDirectory: false)
        }
        state.cachedFlatTree = FileTreeNavigator.flatten(state.treeNodes)
        state.selectedTreeIndex = 25
        state.treeScrollOffset = 0

        ensureTreeVisible(state, contentRows: 10)
        #expect(state.treeScrollOffset == 16)
    }

    @Test
    func `scrollLinesPerTick scales with viewport height`() {
        #expect(scrollLinesPerTick(visibleRows: 10, configured: nil) == 1)
        #expect(scrollLinesPerTick(visibleRows: 24, configured: nil) == 1)
        #expect(scrollLinesPerTick(visibleRows: 48, configured: nil) == 1)
        #expect(scrollLinesPerTick(visibleRows: 200, configured: nil) == 1)
    }

    @Test
    func `scrollLinesPerTick respects configured value`() {
        #expect(scrollLinesPerTick(visibleRows: 48, configured: 1) == 1)
        #expect(scrollLinesPerTick(visibleRows: 48, configured: 20) == 20)
        #expect(scrollLinesPerTick(visibleRows: 48, configured: 0) == 1)
    }

    @Test
    func `tree panel scrollbar drag preserves existing mapping`() {
        let rect = Rect(x: 1, y: 1, width: 10, height: 5)

        #expect(TreePanelLayout.contentWidth(rowCount: 20, in: rect) == 9)
        #expect(TreePanelLayout.verticalScrollIndicatorRect(rowCount: 20, in: rect) == Rect(x: 10, y: 1, width: 1, height: 5))

        let gripOffset = TreePanelLayout.scrollGripOffset(
            rowCount: 20,
            scrollOffset: 0,
            in: rect,
            pointerRow: 2
        )

        #expect(gripOffset == 1)
        #expect(
            TreePanelLayout.scrollOffset(
                rowCount: 20,
                currentOffset: 0,
                in: rect,
                pointerRow: 5,
                gripOffset: gripOffset ?? 0
            ) == 19
        )
    }

    @Test
    func `handleEvent moves cursor for repeated arrow keys`() {
        let sut = makeSUT(fileContent: ["one", "two", "three"])

        let handled = handleEvent(
            event: .key(KeyEvent(keyCode: Key.down.rawValue, eventType: .repeat)),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(handled)
        #expect(sut.state.cursorRow == 1)
    }

    @Test
    func `handleEvent keeps option arrow repeat semantics`() {
        let sut = makeSUT(fileContent: ["alpha beta gamma"])

        let handled = handleEvent(
            event: .key(KeyEvent(keyCode: Key.right.rawValue, modifiers: .alt, eventType: .repeat)),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(handled)
        #expect(sut.state.cursorCol == 6)
    }

    @Test
    func `left arrow wraps to previous line when enabled`() {
        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbon.position = .hidden
        config.editor.arrowKeysWrapAcrossLines = true

        let state = EditorState(rootPath: ".", config: config)
        state.mode = .editor
        state.fileContent = ["ab", "cde"]
        state.cursorRow = 1
        state.cursorCol = 0

        let pipeline = RenderPipeline(
            connection: MockTerminalConnection(size: TerminalSize(columns: 40, rows: 10)),
            columns: 40,
            rows: 10
        )

        let handled = handleEvent(
            event: .key(KeyEvent(keyCode: Key.left.rawValue)),
            state: state,
            pipeline: pipeline
        )

        #expect(handled)
        #expect(state.cursorRow == 0)
        #expect(state.cursorCol == 2)
    }

    @Test
    func `right arrow wraps to next line when enabled`() {
        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbon.position = .hidden
        config.editor.arrowKeysWrapAcrossLines = true

        let state = EditorState(rootPath: ".", config: config)
        state.mode = .editor
        state.fileContent = ["ab", "cde"]
        state.cursorRow = 0
        state.cursorCol = 2

        let pipeline = RenderPipeline(
            connection: MockTerminalConnection(size: TerminalSize(columns: 40, rows: 10)),
            columns: 40,
            rows: 10
        )

        let handled = handleEvent(
            event: .key(KeyEvent(keyCode: Key.right.rawValue)),
            state: state,
            pipeline: pipeline
        )

        #expect(handled)
        #expect(state.cursorRow == 1)
        #expect(state.cursorCol == 0)
    }

    @Test
    func `modifier-only key presses do not scroll the editor to an offscreen cursor`() {
        let sut = makeSUT(fileContent: (0..<80).map(String.init), rows: 12)
        sut.state.cursorRow = 40
        sut.state.scrollOffset = 0

        let handled = handleEvent(
            event: .key(KeyEvent(keyCode: 0, modifiers: .super, eventType: .press)),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(handled)
        #expect(sut.state.cursorRow == 40)
        #expect(sut.state.scrollOffset == 0)
    }

    @Test
    func `handleEvent keeps page navigation working for repeated fn style keys`() {
        let sut = makeSUT(fileContent: (0..<100).map(String.init), rows: 12)

        let handled = handleEvent(
            event: .key(KeyEvent(keyCode: Key.pageDown.rawValue, eventType: .repeat)),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(handled)
        #expect(sut.state.cursorRow == 11)
    }

    @Test
    func `handleEvent ignores repeated escape after leaving the editor`() {
        let sut = makeSUT(fileContent: ["one"])

        let firstHandled = handleEvent(
            event: .key(KeyEvent(keyCode: AsciiKey.escape)),
            state: sut.state,
            pipeline: sut.pipeline
        )
        let repeatedHandled = handleEvent(
            event: .key(KeyEvent(keyCode: AsciiKey.escape, eventType: .repeat)),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(firstHandled)
        #expect(repeatedHandled)
        #expect(sut.state.mode == .tree)
    }

    @Test
    func `insertText invalidates cached file snapshot`() {
        let sut = makeSUT(fileContent: ["hello"])
        _ = sut.state.fileContent
        sut.state.cursorCol = 5

        insertText("!", into: sut.state)

        #expect(sut.state.fileContent == ["hello!"])
        #expect(sut.state.fileLineCount == 1)
    }

    @Test
    func `handleEvent enter invalidates cached file snapshot`() {
        let sut = makeSUT(fileContent: ["hello"])
        _ = sut.state.fileContent
        sut.state.cursorCol = 2

        let handled = handleEvent(
            event: .key(KeyEvent(keyCode: Key.enter.rawValue)),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(handled)
        #expect(sut.state.fileContent == ["he", "llo"])
        #expect(sut.state.cursorRow == 1)
        #expect(sut.state.cursorCol == 0)
    }

    @Test
    func `handleEvent backspace invalidates cached file snapshot`() {
        let sut = makeSUT(fileContent: ["he", "llo"])
        _ = sut.state.fileContent
        sut.state.cursorRow = 1
        sut.state.cursorCol = 0

        let handled = handleEvent(
            event: .key(KeyEvent(keyCode: Key.backspace.rawValue)),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(handled)
        #expect(sut.state.fileContent == ["hello"])
        #expect(sut.state.cursorRow == 0)
        #expect(sut.state.cursorCol == 2)
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
    func `dragging the editor scroll indicator updates the shared scroll offset`() {
        let sut = makeSUT(fileContent: (0..<20).map(String.init), columns: 18, rows: 8)
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
        sut.state.treeNodes = (0..<30).map { i in
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

@Suite
struct KittyCodeSyntaxWiringTests {
    @Test func `language highlighter returns styled json output when bundled resources are available`() async {
        let available = await LanguageHighlighter.ensureArtifacts(for: "json")
        let session = LanguageHighlighter.makeSession(language: "json")
        let lines = session.highlightDocument(source: "true")
        #expect(available)
        #expect(lines.count == 1)
        #expect(lines[0].count == 1)
        #expect(lines[0][0].text == "true")
        #expect(lines[0][0].style != Theme.monokai.defaultStyle)
    }

    @Test func `swift grammar resources are bundled for kittycode`() {
        #expect(LanguageHighlighter.hasBundledResources(for: "swift"))
    }

    @Test func `language highlighter falls back for unsupported languages`() {
        let lines = LanguageHighlighter.highlightDocument(source: "// comment", language: "unknown_lang")
        #expect(lines.count == 1)
        #expect(lines[0].count == 1)
        #expect(lines[0][0].text == "// comment")
    }

    @Test
    @MainActor
    func `EditorState refreshHighlights populates per-line styled output`() {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        state.fileContent = ["true", "42"]
        state.currentLanguage = "json"

        state.refreshHighlights()

        #expect(state.highlightedLines.count == 2)
        #expect(!state.highlightedLine(at: 0).isEmpty)
        #expect(!state.highlightedLine(at: 1).isEmpty)
    }

    @Test
    @MainActor
    func `EditorState fallback highlighting reuses line-based input for unsupported languages`() {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        state.fileContent = ["// comment", "value"]
        state.currentLanguage = "unknown_lang"

        state.refreshHighlights()

        #expect(state.highlightedLines.count == 2)
        #expect(state.highlightedLines[0].map(\.text).joined() == "// comment")
        #expect(state.highlightedLines[1].map(\.text).joined() == "value")
    }

    @Test
    @MainActor
    func `EditorState patches only the affected fallback highlight range`() throws {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        state.currentLanguage = "unknown_lang"
        state.fileContent = ["hello", "world", "tail"]
        state.highlightedLines = [
            [StyledSpan(text: "stale-first", style: .default)],
            [StyledSpan(text: "stale-second", style: .default)],
            [StyledSpan(text: "tail-sentinel", style: .default)],
        ]
        state.cursorRow = 1
        state.cursorCol = 0

        let mutation = try #require(TextOperations.deleteBackward(in: &state.textBuffer, at: &state.textCursor))
        state.textDidChange(mutation)

        #expect(state.fileContent == ["helloworld", "tail"])
        #expect(state.highlightedLines.count == 2)
        #expect(state.highlightedLines[0].map(\.text).joined() == "helloworld")
        #expect(state.highlightedLines[1][0].text == "tail-sentinel")
    }
}

// MARK: - detectLanguage tests

@Suite
@MainActor
struct DetectLanguageTests {
    @Test func `swift extension maps to swift`() {
        #expect(EditorState.detectLanguage(for: "file.swift") == "swift")
    }

    @Test func `uppercase swift extension maps to swift`() {
        #expect(EditorState.detectLanguage(for: "file.SWIFT") == "swift")
    }

    @Test func `json extension maps to json`() {
        #expect(EditorState.detectLanguage(for: "file.json") == "json")
    }

    @Test func `py extension maps to python`() {
        #expect(EditorState.detectLanguage(for: "file.py") == "python")
    }

    @Test func `ts extension maps to typescript`() {
        #expect(EditorState.detectLanguage(for: "file.ts") == "typescript")
    }

    @Test func `unknown extension returns nil`() {
        #expect(EditorState.detectLanguage(for: "file.unknown") == nil)
    }

    @Test func `filename with no extension returns nil`() {
        #expect(EditorState.detectLanguage(for: "Makefile") == nil)
    }
}

// MARK: - BufferManager tests

@Suite
@MainActor
struct BufferManagerTests {
    @Test
    func `open creates a new buffer`() {
        let manager = BufferManager()
        let idx = manager.open(filePath: "/a.swift", fileName: "a.swift", content: "hello", language: "swift")
        #expect(idx == 0)
        #expect(manager.count == 1)
        #expect(manager.activeIndex == 0)
        #expect(manager.activeBuffer?.fileName == "a.swift")
    }

    @Test
    func `open same file twice returns existing index`() {
        let manager = BufferManager()
        let idx1 = manager.open(filePath: "/a.swift", fileName: "a.swift", content: "hello", language: "swift")
        let idx2 = manager.open(filePath: "/a.swift", fileName: "a.swift", content: "hello", language: "swift")
        #expect(idx1 == idx2)
        #expect(manager.count == 1)
    }

    @Test
    func `open two different files yields count 2`() {
        let manager = BufferManager()
        manager.open(filePath: "/a.swift", fileName: "a.swift", content: "a", language: "swift")
        manager.open(filePath: "/b.swift", fileName: "b.swift", content: "b", language: "swift")
        #expect(manager.count == 2)
        #expect(manager.activeIndex == 1)
    }

    @Test
    func `nextTab and prevTab cycle through buffers`() {
        let manager = BufferManager()
        manager.open(filePath: "/a.swift", fileName: "a.swift", content: "a", language: "swift")
        manager.open(filePath: "/b.swift", fileName: "b.swift", content: "b", language: "swift")
        manager.open(filePath: "/c.swift", fileName: "c.swift", content: "c", language: "swift")
        #expect(manager.activeIndex == 2)

        manager.nextTab()
        #expect(manager.activeIndex == 0)

        manager.prevTab()
        #expect(manager.activeIndex == 2)
    }

    @Test
    func `close dirty buffer returns promptSave`() {
        let manager = BufferManager()
        manager.open(filePath: "/a.swift", fileName: "a.swift", content: "a", language: "swift")
        manager.activeBuffer?.isDirty = true

        let result = manager.close(at: 0)
        #expect(result == .promptSave)
        #expect(manager.count == 1)
    }

    @Test
    func `close clean buffer removes it`() {
        let manager = BufferManager()
        manager.open(filePath: "/a.swift", fileName: "a.swift", content: "a", language: "swift")
        manager.open(filePath: "/b.swift", fileName: "b.swift", content: "b", language: "swift")

        let result = manager.close(at: 0)
        #expect(result == .closed)
        #expect(manager.count == 1)
        #expect(manager.activeBuffer?.fileName == "b.swift")
    }

    @Test
    func `forceClose removes dirty buffer`() {
        let manager = BufferManager()
        manager.open(filePath: "/a.swift", fileName: "a.swift", content: "a", language: "swift")
        manager.activeBuffer?.isDirty = true

        manager.forceClose(at: 0)
        #expect(manager.count == 0)
        #expect(manager.isEmpty)
    }
}

// MARK: - Config extension tests

@Suite
struct KittyConfigExtensionTests {
    @Test
    func `old JSON without new fields decodes with defaults`() throws {
        let json = """
        {"keybindingMode": "vim", "treeWidth": 25}
        """
        let config = try JSONDecoder().decode(KittyConfig.self, from: Data(json.utf8))
        #expect(config.keybindingMode == .vim)
        #expect(config.treeWidth == 25)
        #expect(config.fileWatcherEnabled == true)
        #expect(config.autoSave.enabled == false)
        #expect(config.autoSave.interval == 30)
        #expect(config.git.enabled == true)
        #expect(config.git.refreshInterval == 10)
        #expect(config.git.decorations.showLineChanges == true)
        #expect(config.git.decorations.showTabRibbonStatus == true)
        #expect(config.git.decorations.showOpenFilesStatus == true)
        #expect(config.syntax.enabled == true)
        #expect(config.syntax.disabledLanguages.isEmpty)
        #expect(config.tabRibbon.position == .top)
        #expect(config.activityBar.show == true)
        #expect(config.activityBar.position == .left)
        #expect(config.keybindings.tabNext == "ctrl+pagedown")
        #expect(config.keybindings.toggleSidebar == "ctrl+b")
        #expect(config.editor.scrollAccelerationEnabled == true)
        #expect(config.editor.scrollAccelerationWindowMilliseconds == 120)
        #expect(config.editor.scrollAccelerationStepIntervalMilliseconds == 1)
        #expect(config.editor.scrollAccelerationMaxExtraLines == 8)
    }

    @Test
    func `status bar and editor config decode custom values`() throws {
        let json = """
        {
          "editor": {
            "arrowKeysWrapAcrossLines": false,
            "scrollMomentumBlockMilliseconds": 9,
            "scrollAccelerationEnabled": false,
            "scrollAccelerationWindowMilliseconds": 80,
            "scrollAccelerationStepIntervalMilliseconds": 3,
            "scrollAccelerationMaxExtraLines": 4
          },
          "statusBar": {
            "show": false,
            "leftItems": ["file"],
            "rightItems": ["language", "lineEnding", "git"],
            "showContextHints": false
          }
        }
        """

        let config = try JSONDecoder().decode(KittyConfig.self, from: Data(json.utf8))

        #expect(config.editor.arrowKeysWrapAcrossLines == false)
        #expect(config.editor.scrollMomentumBlockMilliseconds == 9)
        #expect(config.editor.scrollAccelerationEnabled == false)
        #expect(config.editor.scrollAccelerationWindowMilliseconds == 80)
        #expect(config.editor.scrollAccelerationStepIntervalMilliseconds == 3)
        #expect(config.editor.scrollAccelerationMaxExtraLines == 4)
        #expect(config.statusBar.show == false)
        #expect(config.statusBar.leftItems == [.file])
        #expect(config.statusBar.rightItems == [.language, .lineEnding, .git])
        #expect(config.statusBar.showContextHints == false)
    }

    @Test
    func `new JSON fields roundtrip correctly`() throws {
        var config = KittyConfig()
        config.autoSave.enabled = true
        config.autoSave.interval = 60
        config.tabRibbon.position = .hidden
        config.editor.scrollMomentumBlockMilliseconds = 7
        config.editor.scrollAccelerationEnabled = false
        config.editor.scrollAccelerationWindowMilliseconds = 70
        config.editor.scrollAccelerationStepIntervalMilliseconds = 4
        config.editor.scrollAccelerationMaxExtraLines = 3
        config.activityBar.show = false
        config.git.decorations.showTabRibbonStatus = false
        config.git.decorations.maxLineDiffBytes = 2048
        config.syntax.disabledLanguages = ["python", "ruby"]

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(KittyConfig.self, from: data)
        #expect(decoded.autoSave.enabled == true)
        #expect(decoded.autoSave.interval == 60)
        #expect(decoded.tabRibbon.position == .hidden)
        #expect(decoded.editor.scrollMomentumBlockMilliseconds == 7)
        #expect(decoded.editor.scrollAccelerationEnabled == false)
        #expect(decoded.editor.scrollAccelerationWindowMilliseconds == 70)
        #expect(decoded.editor.scrollAccelerationStepIntervalMilliseconds == 4)
        #expect(decoded.editor.scrollAccelerationMaxExtraLines == 3)
        #expect(decoded.activityBar.show == false)
        #expect(decoded.git.decorations.showTabRibbonStatus == false)
        #expect(decoded.git.decorations.maxLineDiffBytes == 2048)
        #expect(decoded.syntax.disabledLanguages == ["python", "ruby"])
    }

    @Test
    func `theme new optional fields default to nil`() {
        let theme = KittyConfig.Theme()
        #expect(theme.tabActiveBackground == nil)
        #expect(theme.tabActiveForeground == nil)
        #expect(theme.activityBarBackground == nil)
        #expect(theme.openFilesForeground == nil)
    }
}

@Suite
@MainActor
struct StatusBarAndPromptTests {
    @Test
    func `beginSavePrompt defaults to last selected directory`() {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let state = EditorState(rootPath: rootURL.path, config: KittyConfig())

        state.noteSelectedPath(rootURL.appendingPathComponent("Sources/App/main.swift").path, isDirectory: false)
        state.beginNewFile()
        state.beginSavePrompt()

        #expect(state.prompt?.input == "Sources/App/")
    }

    @Test
    func `statusBarSegments render configured file metadata`() {
        var config = KittyConfig()
        config.statusBar.leftItems = [.file]
        config.statusBar.rightItems = [.language, .lineEnding, .git, .position]

        let state = EditorState(rootPath: ".", config: config)
        state.beginNewFile()
        state.mode = .editor
        state.fileName = "note.swift"
        state.bufferManager.activeBuffer?.fileName = "note.swift"
        state.currentLanguage = "swift"
        state.currentLineEnding = .crlf
        state.fileContent = ["abc"]
        state.cursorRow = 0
        state.cursorCol = 2
        state.fileStatusProvider = TestGitProvider(
            summary: .init(modified: 3, added: 1, deleted: 2, conflicted: 1)
        )

        let segments = state.statusBarSegments(columns: 80, rows: 24)

        #expect(segments.left.contains("note.swift"))
        #expect(segments.right.contains("│"))
        #expect(segments.right.contains("swift"))
        #expect(segments.right.contains("CRLF"))
        #expect(segments.right.contains("M3 A1 D2 !1"))
        #expect(segments.right.contains("Ln 1, Col 3"))
    }

    @Test
    func `writeBufferToDisk preserves configured line endings`() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let state = EditorState(rootPath: rootURL.path, config: KittyConfig())
        state.beginNewFile()
        state.fileContent = ["alpha", "beta", ""]
        state.currentLineEnding = .crlf

        let savedURL = rootURL.appendingPathComponent("notes/output.txt")
        let saveSucceeded = state.writeBufferToDisk(at: savedURL.path)

        #expect(saveSucceeded)
        #expect(try String(contentsOf: savedURL, encoding: .utf8) == "alpha\r\nbeta\r\n")
        #expect(state.currentLineEnding == .crlf)
        #expect(state.bufferManager.activeBuffer?.lineEnding == .crlf)
    }
}

// MARK: - Multi-buffer integration tests

@Suite
@MainActor
struct MultiBufferIntegrationTests {
    @Test
    func `switching tabs preserves cursor position`() {
        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbon.position = .hidden
        let state = EditorState(rootPath: ".", config: config)

        // Simulate opening first file via bufferManager
        state.bufferManager.open(filePath: "/a.txt", fileName: "a.txt", content: "hello world", language: nil)
        state.restoreStateFromActiveBuffer()
        state.cursorRow = 0
        state.cursorCol = 5

        // Simulate opening second file
        state.saveStateToActiveBuffer()
        state.bufferManager.open(filePath: "/b.txt", fileName: "b.txt", content: "line1\nline2\nline3", language: nil)
        state.restoreStateFromActiveBuffer()
        state.cursorRow = 2
        state.cursorCol = 3

        // Switch back to first file
        state.switchToTab(0)
        #expect(state.cursorRow == 0)
        #expect(state.cursorCol == 5)
        #expect(state.fileName == "a.txt")

        // Switch back to second file
        state.switchToTab(1)
        #expect(state.cursorRow == 2)
        #expect(state.cursorCol == 3)
        #expect(state.fileName == "b.txt")
    }

    @Test
    func `textDidChange marks active buffer dirty`() {
        var config = KittyConfig()
        config.activityBar.show = false
        let state = EditorState(rootPath: ".", config: config)

        state.bufferManager.open(filePath: "/a.txt", fileName: "a.txt", content: "hello", language: nil)
        state.restoreStateFromActiveBuffer()
        #expect(state.bufferManager.activeBuffer?.isDirty == false)

        state.textDidChange()
        #expect(state.bufferManager.activeBuffer?.isDirty == true)
    }

    @Test
    @MainActor
    func `opening and restoring a file preserves exact document snapshots`() async throws {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: rootURL) }

        let firstFileURL = rootURL.appendingPathComponent("first.txt")
        let secondFileURL = rootURL.appendingPathComponent("second.txt")
        try "alpha\nbeta\n".write(to: firstFileURL, atomically: true, encoding: .utf8)
        try "gamma".write(to: secondFileURL, atomically: true, encoding: .utf8)

        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbon.position = .hidden
        let state = EditorState(rootPath: rootURL.path, config: config)

        func waitUntil(_ condition: @escaping () -> Bool) async {
            for _ in 0..<200 {
                if condition() {
                    return
                }
                try? await Task.sleep(for: .milliseconds(5))
            }
            Issue.record("Timed out waiting for asynchronous file open")
        }

        state.openFilePath(firstFileURL.path, name: "first.txt")
        await waitUntil { state.fileName == "first.txt" }
        #expect(state.fileContent == ["alpha", "beta", ""])
        #expect(state.documentText == "alpha\nbeta\n")

        state.openFilePath(secondFileURL.path, name: "second.txt")
        await waitUntil { state.fileName == "second.txt" }
        state.switchToTab(0)

        #expect(state.fileName == "first.txt")
        #expect(state.fileContent == ["alpha", "beta", ""])
        #expect(state.documentText == "alpha\nbeta\n")
    }
}

// MARK: - Runtime regression tests

@Suite
@MainActor
struct RuntimeRegressionsTests {
    private func makeSUT(
        fileContent: [String] = [""],
        columns: Int = 80,
        rows: Int = 24,
        activityBar: Bool = false,
        tabRibbon: KittyConfig.TabRibbonPosition = .hidden
    ) -> (state: EditorState, pipeline: RenderPipeline) {
        var config = KittyConfig()
        config.activityBar.show = activityBar
        config.tabRibbon.position = tabRibbon
        let state = EditorState(rootPath: ".", config: config)
        state.fileContent = fileContent
        let pipeline = RenderPipeline(
            connection: MockTerminalConnection(size: TerminalSize(columns: columns, rows: rows)),
            columns: columns,
            rows: rows
        )
        return (state, pipeline)
    }

    // --- Editor content placement ---

    @Test
    func `editor content renders at contentStartRow not row 1`() {
        let sut = makeSUT(fileContent: ["hello"], columns: 40, rows: 10)
        sut.state.mode = .editor
        sut.state.sidebarCollapsed = true
        sut.state.refreshHighlights()
        // Without tab ribbon, contentStartRow = 0
        render(pipeline: sut.pipeline, state: sut.state)

        // Without title bar, row 0 should have editor content (line numbers + text)
        let row1Chars = (0..<40).map { sut.pipeline.buffer[0, $0].character }
        let row1Text = String(row1Chars)
        #expect(row1Text.contains("hello"), "Editor content should appear at row 0 (contentStartRow)")
    }

    @Test
    func `editor content starts at row 2 when tab ribbon is shown`() {
        let cols = 40
        let sut = makeSUT(columns: cols, rows: 10, tabRibbon: .top)
        sut.state.mode = .editor
        sut.state.sidebarCollapsed = true
        sut.state.bufferManager.open(filePath: "/a.txt", fileName: "a.txt", content: "world", language: nil)
        sut.state.restoreStateFromActiveBuffer()
        sut.state.refreshHighlights()

        render(pipeline: sut.pipeline, state: sut.state)

        // Row 0: tab ribbon, Row 1: editor content
        let row2Chars = (0..<cols).map { sut.pipeline.buffer[1, $0].character }
        let row2Text = String(row2Chars)
        #expect(row2Text.contains("world"), "Editor content should appear at row 1 below tab ribbon")

        // Row 0 should NOT contain editor content (it's the tab ribbon)
        let row1Chars = (0..<cols).map { sut.pipeline.buffer[0, $0].character }
        let row1Text = String(row1Chars)
        #expect(!row1Text.contains("world"), "Tab ribbon row should not contain editor text")
    }

    @Test
    func `tab ribbon fills full terminal width`() {
        let cols = 40
        let sut = makeSUT(fileContent: ["x"], columns: cols, rows: 10, tabRibbon: .top)
        sut.state.bufferManager.open(filePath: "/a.txt", fileName: "a.txt", content: "x", language: nil)
        sut.state.restoreStateFromActiveBuffer()

        render(pipeline: sut.pipeline, state: sut.state)

        // Row 1 is the tab ribbon — every column should be non-null (filled with background)
        for col in 0..<cols {
            let cell = sut.pipeline.buffer[1, col]
            #expect(cell.character != "\0", "Tab ribbon row should be filled at col \(col)")
        }
    }

    @Test
    func `editor gutter renders git line decorations`() {
        let sut = makeSUT(fileContent: ["hello"], columns: 40, rows: 10)
        sut.state.mode = .editor
        sut.state.sidebarCollapsed = true
        sut.state.bufferManager.open(filePath: "/note.txt", fileName: "note.txt", content: "hello", language: nil)
        sut.state.restoreStateFromActiveBuffer()
        sut.state.bufferManager.activeBuffer?.gitLineDecorations = GitLineDecorations(markers: [0: .added])
        sut.state.gitLineDecorationProvider = TestGitProvider()

        render(pipeline: sut.pipeline, state: sut.state)

        #expect(sut.pipeline.buffer[0, 0].character == "+")
        #expect(sut.pipeline.buffer[0, 3].character == "1")
    }

    @Test
    func `tab ribbon renders git status indicators for open buffers`() {
        let cols = 40
        let sut = makeSUT(fileContent: ["x"], columns: cols, rows: 10, tabRibbon: .top)
        sut.state.bufferManager.open(filePath: "/note.txt", fileName: "note.txt", content: "x", language: nil)
        sut.state.restoreStateFromActiveBuffer()
        sut.state.fileStatusProvider = TestGitProvider(statuses: ["/note.txt": .modified])

        render(pipeline: sut.pipeline, state: sut.state)

        let mCol = (0..<cols).first { sut.pipeline.buffer[0, $0].character == "M" }
        #expect(mCol != nil, "Expected 'M' indicator in tab ribbon row")
        if let col = mCol {
            let cell = sut.pipeline.buffer[0, col]
            #expect(cell.style == sut.state.colorScheme.gitModified, "M indicator should use gitModified style")
        }
    }

    @Test
    func `open files panel renders git status indicators`() {
        let cols = 40
        let sut = makeSUT(columns: cols, rows: 10)
        sut.state.treePanelWidth = 16
        sut.state.activeSidebarPanel = .openDocuments
        sut.state.bufferManager.open(filePath: "/note.txt", fileName: "note.txt", content: "x", language: nil)
        sut.state.restoreStateFromActiveBuffer()
        sut.state.fileStatusProvider = TestGitProvider(statuses: ["/note.txt": .modified])

        render(pipeline: sut.pipeline, state: sut.state)

        let mCol = (0..<16).first { sut.pipeline.buffer[0, $0].character == "M" }
        #expect(mCol != nil, "Expected 'M' indicator in open files panel")
        if let col = mCol {
            let cell = sut.pipeline.buffer[0, col]
            #expect(cell.style == sut.state.colorScheme.gitModified, "M indicator should use gitModified style")
        }
    }

    // --- Activity bar ---

    @Test
    func `activity bar renders in the first 3 columns`() {
        let sut = makeSUT(fileContent: ["test"], columns: 40, rows: 10, activityBar: true)
        sut.state.mode = .editor
        render(pipeline: sut.pipeline, state: sut.state)

        // Activity bar renders at columns 0-2, contentStartRow=1
        // Column 1 (centered) should have an icon character for the first activity bar item
        let iconCell = sut.pipeline.buffer[1, 1]
        #expect(iconCell.character != " " || iconCell.style != .default,
                "Activity bar center column should have styled content")
    }

    @Test
    func `ActivityBar width is 3`() {
        #expect(ActivityBar.width == 3)
    }

    @Test
    func `ctrl n creates an editable untitled buffer`() {
        let sut = makeSUT(columns: 40, rows: 10)
        sut.state.mode = .tree
        sut.state.sidebarCollapsed = true

        let handled = handleEvent(
            event: .key(KeyEvent(keyCode: AsciiKey.n, modifiers: .ctrl)),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(handled)
        #expect(sut.state.bufferManager.count == 1)
        #expect(sut.state.fileName == "Untitled")
        #expect(sut.state.mode == .editor)

        render(pipeline: sut.pipeline, state: sut.state)

        #expect(sut.pipeline.cursorRow != nil)
        #expect(sut.pipeline.cursorCol != nil)
    }

    @Test
    func `save prompt writes a new file under the project root`() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true,
            attributes: nil
        )

        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbon.position = .hidden
        let state = EditorState(rootPath: rootURL.path, config: config)
        let pipeline = RenderPipeline(
            connection: MockTerminalConnection(size: TerminalSize(columns: 40, rows: 10)),
            columns: 40,
            rows: 10
        )

        state.beginNewFile()
        insertText("hello", into: state)

        let startedPrompt = handleEvent(
            event: .key(KeyEvent(keyCode: AsciiKey.o, modifiers: .ctrl)),
            state: state,
            pipeline: pipeline
        )
        let enteredPath = handleEvent(
            event: .key(KeyEvent(keyCode: 0, associatedText: "notes/new.txt")),
            state: state,
            pipeline: pipeline
        )
        let submittedPrompt = handleEvent(
            event: .key(KeyEvent(keyCode: Key.enter.rawValue)),
            state: state,
            pipeline: pipeline
        )

        let savedURL = rootURL.appendingPathComponent("notes/new.txt")

        #expect(startedPrompt)
        #expect(enteredPath)
        #expect(submittedPrompt)
        #expect(state.prompt == nil)
        #expect(state.filePath == savedURL.path)
        #expect(state.fileName == "new.txt")
        #expect(FileManager.default.fileExists(atPath: savedURL.path))
        #expect(try String(contentsOf: savedURL, encoding: .utf8) == "hello")
    }

    // --- Mouse coordinate handling (1-based SGR to 0-based screen) ---

    @Test
    func `editor click converts 1-based mouse coordinates correctly`() {
        let sut = makeSUT(fileContent: ["line one", "line two", "line three"], columns: 40, rows: 10)
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

        #expect(sut.state.selectedTreeIndex == 0, "First content row click should select tree index 0")
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
        #expect(sut.state.contextMenu?.items.map(\.title) == ["Open", "Open and Pin", "Save Here…"])
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
                    return contextMenuItemIndex(at: mouse, state: sut.state, columns: 40, rows: 10) == 0 ? mouse : nil
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

    // --- Scroll position preservation ---

    @Test
    func `tree refresh preserves scroll offset`() async {
        let sut = makeSUT(columns: 40, rows: 10)
        sut.state.treeScrollOffset = 5
        sut.state.selectedTreeIndex = 7
        sut.state.treeNodes = (0..<20).map { i in
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
        sut.state.treeNodes = (0..<20).map { i in
            FileNode(name: "file\(i).txt", path: "/file\(i).txt", isDirectory: false)
        }
        sut.state.cachedFlatTree = FileTreeNavigator.flatten(sut.state.treeNodes)

        // Shrink to 10 items
        sut.state.treeNodes = (0..<10).map { i in
            FileNode(name: "file\(i).txt", path: "/file\(i).txt", isDirectory: false)
        }
        sut.state.refreshFlatTree()

        // Scroll and selection should be clamped, not reset to 0
        let maxIndex = sut.state.cachedFlatTree.count - 1
        #expect(sut.state.treeScrollOffset <= maxIndex)
        #expect(sut.state.selectedTreeIndex <= maxIndex)
    }

    // --- Empty editor ---

    @Test
    func `empty editor message renders at contentStartRow not row 1`() {
        let sut = makeSUT(columns: 60, rows: 10, tabRibbon: .top)
        sut.state.mode = .editor
        sut.state.sidebarCollapsed = true
        // With tab ribbon but no buffers, showTabRibbon=false (count=0)
        // So contentStartRow=1. Let's just verify render doesn't crash
        render(pipeline: sut.pipeline, state: sut.state)

        // No tab ribbon (no buffers), content starts at row 0
        // The empty editor message should be somewhere in the middle rows
        let midRow = 0 + (10 - 1) / 2  // contentStartRow + contentRows/2
        let rowChars = (0..<60).map { sut.pipeline.buffer[midRow, $0].character }
        let rowText = String(rowChars).trimmingCharacters(in: .whitespaces)
        #expect(rowText.contains("Open a file"))
    }

    // --- Status bar at bottom ---

    @Test
    func `status bar renders on the last row`() {
        let rows = 10
        let sut = makeSUT(fileContent: ["test"], columns: 40, rows: rows)
        sut.state.mode = .editor
        render(pipeline: sut.pipeline, state: sut.state)

        let lastRowChars = (0..<40).map { sut.pipeline.buffer[rows - 1, $0].character }
        let lastRowText = String(lastRowChars)
        // Status bar should contain file name or language
        #expect(lastRowText.contains("Untitled") || lastRowText.contains("plain text"))
    }

    @Test
    func `no empty blank row between content and status bar`() {
        let rows = 10
        let sut = makeSUT(fileContent: (0..<20).map { "line \($0)" }, columns: 40, rows: rows)
        sut.state.mode = .editor
        render(pipeline: sut.pipeline, state: sut.state)

        // Row rows-2 (second to last) should have editor content, not be blank
        let penultimateChars = (0..<40).map { sut.pipeline.buffer[rows - 2, $0].character }
        let penultimateText = String(penultimateChars).trimmingCharacters(in: .whitespaces)
        #expect(!penultimateText.isEmpty, "Second-to-last row should have content, not be blank")
    }

    // --- Layout with activity bar + tab ribbon ---

    @Test
    func `full layout with activity bar and tab ribbon renders without overlap`() {
        let sut = makeSUT(
            fileContent: ["hello world"],
            columns: 60,
            rows: 12,
            activityBar: true,
            tabRibbon: .top
        )
        sut.state.mode = .editor
        sut.state.treePanelWidth = 15
        sut.state.bufferManager.open(filePath: "/a.txt", fileName: "a.txt", content: "hello world", language: nil)
        sut.state.restoreStateFromActiveBuffer()

        render(pipeline: sut.pipeline, state: sut.state)

        // Row 0: tab ribbon (full width)
        // Rows 1-10: activity bar (cols 0-2) + sidebar (cols 3-17) + separator (col 18) + editor (cols 19+)
        // Row 11: status bar

        // Tab ribbon at row 0
        let tabChar = sut.pipeline.buffer[0, 0].character
        #expect(tabChar != "\0", "Tab ribbon should fill from column 0")

        // Editor content at row 1 (contentStartRow=1)
        let editorArea = (19..<60).map { sut.pipeline.buffer[1, $0].character }
        let editorText = String(editorArea).trimmingCharacters(in: .whitespaces)
        #expect(editorText.contains("hello") || editorText.contains("1"),
                "Editor area should have content at row 1")

        // Status bar at last row
        let statusChars = (0..<60).map { sut.pipeline.buffer[11, $0].character }
        let statusText = String(statusChars)
        #expect(statusText.contains("a.txt") || statusText.contains("plain text"))
    }

    // --- Sidebar toggle ---

    @Test
    func `toggling sidebar resets layout cleanly on re-render`() {
        let sut = makeSUT(fileContent: ["content line"], columns: 40, rows: 10)
        sut.state.mode = .editor
        sut.state.treePanelWidth = 10

        // Render with sidebar
        sut.state.sidebarCollapsed = false
        renderFrame(pipeline: sut.pipeline, state: sut.state)

        // Re-render without sidebar using the same top-level entry point as the app.
        sut.state.sidebarCollapsed = true
        renderFrame(pipeline: sut.pipeline, state: sut.state)

        // The separator column from the previous render should not persist
        // Editor should now start at column 0 (no sidebar)
        let row1Chars = (0..<40).map { sut.pipeline.buffer[0, $0].character }
        let row1Text = String(row1Chars).trimmingCharacters(in: .whitespaces)
        #expect(row1Text.contains("content") || row1Text.contains("1"),
                "Editor should render from column 0 when sidebar is collapsed")
    }

    @Test
    func `scrolling the tree repaints the top visible row`() throws {
        let sut = makeSUT(columns: 40, rows: 10)
        sut.state.sidebarCollapsed = false
        sut.state.treePanelWidth = 18
        sut.state.treeNodes = (0..<20).map { i in
            FileNode(name: String(format: "file%02d.txt", i), path: "/file\(i).txt", isDirectory: false)
        }
        sut.state.cachedFlatTree = FileTreeNavigator.flatten(sut.state.treeNodes)

        renderFrame(pipeline: sut.pipeline, state: sut.state)
        try sut.pipeline.flush()

        sut.state.treeScrollOffset = 1
        renderFrame(pipeline: sut.pipeline, state: sut.state)

        let layout = LayoutMetrics(state: sut.state, columns: sut.pipeline.columns, rows: sut.pipeline.rows)
        let topRow = layout.contentStartRow
        let treeStartCol = layout.activityBarWidth
        let treeEndCol = treeStartCol + layout.sidebarWidth

        let topRowHasDirtyTreeCell = (treeStartCol..<treeEndCol).contains { col in
            sut.pipeline.buffer.dirty.isDirty(topRow * sut.pipeline.columns + col)
        }

        #expect(topRowHasDirtyTreeCell, "Top visible tree row should be repainted after scrolling")
    }

    @Test
    func `dismissing prompt clears overlay chrome on next frame`() throws {
        let sut = makeSUT(columns: 40, rows: 10)
        sut.state.beginNewFile()
        sut.state.mode = .editor
        sut.state.beginSavePrompt()

        renderFrame(pipeline: sut.pipeline, state: sut.state)

        let promptCorner = try #require(
            (0..<10).lazy.compactMap { row in
                (0..<40).lazy.compactMap { col in
                    sut.pipeline.buffer[row, col].character == "┌" ? (row, col) : nil
                }.first
            }.first
        )

        sut.state.prompt = nil
        renderFrame(pipeline: sut.pipeline, state: sut.state)

        #expect(sut.pipeline.buffer[promptCorner.0, promptCorner.1].character != "┌")
    }
}

// MARK: - Scroll rendering regression tests

@Suite
@MainActor
struct ScrollRenderingTests {
    private func makeSUT(
        lineCount: Int = 100,
        columns: Int = 40,
        rows: Int = 12
    ) -> (state: EditorState, pipeline: RenderPipeline) {
        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbon.position = .hidden
        config.statusBar.show = false
        let state = EditorState(rootPath: ".", config: config)
        state.sidebarCollapsed = true
        state.mode = .editor
        state.fileContent = (0..<lineCount).map { "line \($0) content here" }
        state.refreshHighlights()
        let pipeline = RenderPipeline(
            connection: MockTerminalConnection(size: TerminalSize(columns: columns, rows: rows)),
            columns: columns,
            rows: rows
        )
        return (state, pipeline)
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
        let rowChars = (0..<40).map { sut.pipeline.buffer[contentRow, $0].character }
        let rowText = String(rowChars)
        #expect(rowText.contains("line 3"), "First editor row should show line 3 after scrolling down, got: \(rowText)")
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
        let rowChars = (0..<40).map { sut.pipeline.buffer[contentRow, $0].character }
        let rowText = String(rowChars)
        #expect(rowText.contains("line 7"), "First editor row should show line 7 after scrolling up, got: \(rowText)")
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
        for row in 0..<12 {
            for col in 0..<cols {
                if sut.pipeline.buffer.dirty.isDirty(row * cols + col) {
                    dirtyCount += 1
                }
            }
        }

        // Without pre-shift, all ~440 content cells would be dirty.
        // With pre-shift, only the new bottom row + line number changes should be dirty.
        // Line numbers change by 1 digit on every row, so expect roughly:
        //   1 full row (new content) + small gutter changes ≈ < 220 cells
        let totalContentCells = 11 * cols
        #expect(dirtyCount < totalContentCells, "Dirty cells (\(dirtyCount)) should be less than total content cells (\(totalContentCells))")
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
        for row in 0..<12 {
            for col in 0..<cols {
                if sut.pipeline.buffer.dirty.isDirty(row * cols + col) {
                    dirtyCount += 1
                }
            }
        }

        let totalContentCells = 11 * cols
        #expect(dirtyCount < totalContentCells, "Dirty cells (\(dirtyCount)) should be less than total content cells (\(totalContentCells))")
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
        state.fileContent = (0..<100).map { "line \($0) content here" }
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

        #expect(scrolledSize < initialSize, "Scrolled flush (\(scrolledSize) bytes) should be smaller than initial flush (\(initialSize) bytes)")
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
        let rowChars = (0..<40).map { sut.pipeline.buffer[contentRow, $0].character }
        let rowText = String(rowChars)
        #expect(rowText.contains("line 50"), "First editor row should show line 50 after large jump, got: \(rowText)")
    }

    @Test
    func `multiple consecutive scrolls produce correct content`() throws {
        let sut = makeSUT()
        renderFrame(pipeline: sut.pipeline, state: sut.state)
        try sut.pipeline.flush()

        // Scroll down 5 times by 1
        for i in 1...5 {
            sut.state.scrollOffset = i
            renderFrame(pipeline: sut.pipeline, state: sut.state)
            try sut.pipeline.flush()
        }

        let contentRow = 0
        let rowChars = (0..<40).map { sut.pipeline.buffer[contentRow, $0].character }
        let rowText = String(rowChars)
        #expect(rowText.contains("line 5"), "After 5 scroll-down steps, first row should show line 5, got: \(rowText)")
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
        let rowChars = (0..<40).map { sut.pipeline.buffer[contentRow, $0].character }
        let rowText = String(rowChars)
        #expect(rowText.contains("line 0"), "After scroll down+up, first row should show line 0, got: \(rowText)")
    }

    @Test
    func `scrolling through an overheight wrapped line keeps later wrapped content visible`() throws {
        let mock = MockTerminalConnection(size: TerminalSize(columns: 8, rows: 6))
        let pipeline = RenderPipeline(connection: mock, columns: 8, rows: 6)

        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbon.position = .hidden
        config.statusBar.show = false
        config.editor.wrapLines = true
        config.editor.scrollAccelerationEnabled = false
        let state = EditorState(rootPath: ".", config: config)
        state.sidebarCollapsed = true
        state.mode = .editor
        state.fileContent = ["AAAABBBBCCCCDDDDEEEEFFFFGGGGHHHH", "after"]
        state.refreshHighlights()

        renderFrame(pipeline: pipeline, state: state)

        for _ in 0..<4 {
            handleMouse(
                MouseEvent(button: .scrollDown, row: 1, col: 8, kind: .press),
                state: state,
                pipeline: pipeline
            )
        }

        #expect(state.scrollOffset == 0)
        #expect(state.wrapRowOffset == 4)

        renderFrame(pipeline: pipeline, state: state)

        let topRowText = String((0..<8).map { pipeline.buffer[0, $0].character })
        #expect(topRowText.contains("EEEE"), "Expected wrapped continuation to remain visible after scrolling, got: \(topRowText)")

        let lastContentRowText = String((0..<8).map { pipeline.buffer[4, $0].character })
        #expect(lastContentRowText.contains("afte"), "Expected following line to appear after wrapped continuation rows, got: \(lastContentRowText)")
    }

    @Test
    func `accelerating into wrapped content edge does not crash or leave invalid state`() async throws {
        let mock = MockTerminalConnection(size: TerminalSize(columns: 8, rows: 6))
        let pipeline = RenderPipeline(connection: mock, columns: 8, rows: 6)

        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbon.position = .hidden
        config.statusBar.show = false
        config.editor.wrapLines = true
        config.editor.scrollAccelerationEnabled = true
        config.editor.scrollAccelerationWindowMilliseconds = 200
        config.editor.scrollAccelerationStepIntervalMilliseconds = 1
        config.editor.scrollAccelerationMaxExtraLines = 8
        let state = EditorState(rootPath: ".", config: config)
        state.sidebarCollapsed = true
        state.mode = .editor
        state.fileContent = ["AAAABBBBCCCCDDDDEEEEFFFFGGGGHHHH", "after", "tail", "done"]
        state.refreshHighlights()

        renderFrame(pipeline: pipeline, state: state)

        for _ in 0..<12 {
            handleMouse(
                MouseEvent(button: .scrollDown, row: 1, col: 8, kind: .press),
                state: state,
                pipeline: pipeline
            )
        }

        let deadline = Date().addingTimeInterval(1)
        while (state.pendingAcceleratedScrollLines != 0 || state.scrollAccelerationTask != nil),
              Date() < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }

        #expect(state.scrollOffset == 3)
        #expect(state.wrapRowOffset == 0)
        renderFrame(pipeline: pipeline, state: state)

        #expect(state.pendingAcceleratedScrollLines == 0)
        #expect(state.scrollAccelerationTask == nil)

        let contentRows = (0..<5).map { row in
            String((0..<8).map { pipeline.buffer[row, $0].character })
        }
        let hasDone = contentRows.contains { $0.contains("done") || $0.contains("done".prefix(4)) }
        #expect(hasDone, "Expected bottom content to remain renderable after accelerated scrolling, got: \(contentRows)")
    }
}

private struct TestGitProvider: FileStatusProvider, GitLineDecorationProvider {
    var statuses: [String: FileStatus] = [:]
    var decorations: [String: GitLineDecorations] = [:]
    var branchName: String? = nil
    var summary: FileStatusSummary = .init()

    func status(for path: String) -> FileStatus? {
        statuses[path]
    }

    func refresh() async {}

    func lineDecorations(for path: String, lines _: [String]) async -> GitLineDecorations {
        decorations[path] ?? .empty
    }
}

// MARK: - Preview mode tests

@Suite
@MainActor
struct PreviewModeTests {
    @Test
    func `openPreview creates a preview buffer`() {
        let manager = BufferManager()
        let idx = manager.openPreview(filePath: "/a.txt", fileName: "a.txt", content: "hello", language: nil)
        #expect(idx == 0)
        #expect(manager.count == 1)
        #expect(manager.activeBuffer?.isPreview == true)
    }

    @Test
    func `openPreview replaces existing preview buffer`() {
        let manager = BufferManager()
        manager.openPreview(filePath: "/a.txt", fileName: "a.txt", content: "hello", language: nil)
        manager.openPreview(filePath: "/b.txt", fileName: "b.txt", content: "world", language: nil)
        #expect(manager.count == 1)
        #expect(manager.activeBuffer?.fileName == "b.txt")
        #expect(manager.activeBuffer?.isPreview == true)
    }

    @Test
    func `pinBuffer removes preview status`() {
        let manager = BufferManager()
        manager.openPreview(filePath: "/a.txt", fileName: "a.txt", content: "hello", language: nil)
        manager.pinBuffer(at: 0)
        #expect(manager.activeBuffer?.isPreview == false)
        // Opening another preview should NOT replace the pinned buffer
        manager.openPreview(filePath: "/b.txt", fileName: "b.txt", content: "world", language: nil)
        #expect(manager.count == 2)
    }

    @Test
    func `editing auto-pins preview buffer`() {
        var config = KittyConfig()
        config.activityBar.show = false
        config.tabRibbon.persistence = .preview
        let state = EditorState(rootPath: ".", config: config)
        state.bufferManager.openPreview(filePath: "/a.txt", fileName: "a.txt", content: "hello", language: nil)
        state.restoreStateFromActiveBuffer()
        #expect(state.bufferManager.activeBuffer?.isPreview == true)

        state.textDidChange()
        #expect(state.bufferManager.activeBuffer?.isPreview == false)
    }

    @Test
    func `preview index returns nil when no preview buffers exist`() {
        let manager = BufferManager()
        manager.open(filePath: "/a.txt", fileName: "a.txt", content: "hello", language: nil)
        #expect(manager.previewIndex == nil)
    }
}

// MARK: - Async grammar guard tests

@Suite
@MainActor
struct AsyncGrammarGuardTests {
    @Test
    func `scroll position unchanged after refreshHighlights`() {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        state.fileContent = (0..<50).map { "line \($0)" }
        state.scrollOffset = 20
        state.hScrollOffset = 5
        state.currentLanguage = "json"

        state.refreshHighlights()

        #expect(state.scrollOffset == 20)
        #expect(state.hScrollOffset == 5)
    }

    @Test
    func `isLoadingGrammar defaults to false`() {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        #expect(state.isLoadingGrammar == false)
    }
}

// MARK: - Tab persistence config tests

@Suite
struct TabPersistenceConfigTests {
    @Test
    func `tabPersistence defaults to pinned`() {
        let config = KittyConfig()
        #expect(config.tabRibbon.persistence == .pinned)
    }

    @Test
    func `tabPersistence decodes from JSON`() throws {
        let json = """
        {"tabRibbon": {"persistence": "preview"}}
        """
        let config = try JSONDecoder().decode(KittyConfig.self, from: Data(json.utf8))
        #expect(config.tabRibbon.persistence == .preview)
    }

    @Test
    func `old JSON without tabPersistence uses default`() throws {
        let json = """
        {"keybindingMode": "nano"}
        """
        let config = try JSONDecoder().decode(KittyConfig.self, from: Data(json.utf8))
        #expect(config.tabRibbon.persistence == .pinned)
    }
}

// MARK: - LayoutMetrics Tests

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
        #expect(layout.contentRows == 22) // rows - 1 - tabRows = 24 - 1 - 1 = 22
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

// MARK: - resolvedStyle Tests

@Suite
struct ResolvedStyleTests {
    @Test
    func `resolvedStyle returns nil for nil color`() {
        let theme = KittyConfig.Theme()
        #expect(theme.resolvedStyle(nil) == nil)
    }

    @Test
    func `resolvedStyle returns style for non-nil color`() {
        let theme = KittyConfig.Theme()
        let color = ColorRGB(r: 0xff, g: 0x00, b: 0x00)
        let style = theme.resolvedStyle(color)
        #expect(style != nil)
        #expect(style?.fg == Color.rgb(r: 0xff, g: 0x00, b: 0x00))
        #expect(style?.bold == false)
    }

    @Test
    func `resolvedStyle with bold flag`() {
        let theme = KittyConfig.Theme()
        let color = ColorRGB(r: 0x00, g: 0xff, b: 0x00)
        let style = theme.resolvedStyle(color, bold: true)
        #expect(style != nil)
        #expect(style?.bold == true)
    }
}

// MARK: - Syntax config tests

@Suite
@MainActor
struct SyntaxConfigurationTests {
    @Test
    func `syntaxHighlighting=false produces plain spans`() {
        var config = KittyConfig()
        config.syntax.enabled = false
        let state = EditorState(rootPath: ".", config: config)
        state.fileContent = ["func hello() {", "}"]
        state.currentLanguage = "swift"

        state.refreshHighlights()

        #expect(state.highlightedLines.count == 2)
        #expect(state.highlightedLines[0].count == 1)
        #expect(state.highlightedLines[0][0].text == "func hello() {")
    }

    @Test
    func `disabled language produces plain spans`() {
        var config = KittyConfig()
        config.syntax.disabledLanguages = ["swift"]
        let state = EditorState(rootPath: ".", config: config)
        state.fileContent = ["let x = 42"]
        state.currentLanguage = "swift"

        state.refreshHighlights()

        #expect(state.highlightedLines.count == 1)
        #expect(state.highlightedLines[0].count == 1)
        #expect(state.highlightedLines[0][0].text == "let x = 42")
    }
}

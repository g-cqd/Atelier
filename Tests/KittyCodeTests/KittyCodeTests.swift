import Foundation
import KittyCodecs
import KittyFileTree
import KittyRenderer
import KittySyntax
import KittyTerminal
import KittyText
import Testing
@testable import KittyCode

@Suite("KittyCode Config")
struct KittyCodeConfigTests {
    @Test("ColorRGB parses hex string")
    func colorRGBHexParsing() {
        let parsed = ColorRGB(hex: "#1e2f3a")
        #expect(parsed != nil)
        #expect(parsed?.r == 0x1e)
        #expect(parsed?.g == 0x2f)
        #expect(parsed?.b == 0x3a)
    }

    @Test("ColorRGB codable supports hex string")
    func colorRGBCodableHex() throws {
        let json = "\"#abcdef\""
        let data = Data(json.utf8)
        let color = try JSONDecoder().decode(ColorRGB.self, from: data)
        #expect(color == ColorRGB(r: 0xab, g: 0xcd, b: 0xef))
    }

    @Test("ColorRGB rejects invalid hex")
    func colorRGBInvalidHex() {
        #expect(ColorRGB(hex: "#zzz999") == nil)
        #expect(ColorRGB(hex: "#12345") == nil)
    }

    @Test("Color scheme uses terminal default backgrounds")
    @MainActor
    func colorSchemeUsesDefaultBackgrounds() {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        #expect(state.colorScheme.editorText.bg == .default)
        #expect(state.colorScheme.treeBg.bg == .default)
        #expect(state.colorScheme.statusBar.bg == .default)
    }
}

@Suite("KittyCode Navigation")
@MainActor
struct KittyCodeNavigationTests {
    private func makeSUT(fileContent: [String], columns: Int = 80, rows: Int = 24) -> (state: EditorState, pipeline: RenderPipeline) {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        state.mode = .editor
        state.fileContent = fileContent

        let pipeline = RenderPipeline(
            connection: MockTerminalConnection(size: TerminalSize(columns: columns, rows: rows)),
            columns: columns,
            rows: rows
        )

        return (state, pipeline)
    }

    @Test("Word jump forward moves to next token")
    func jumpForward() {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        state.fileContent = ["alpha   beta"]
        state.cursorRow = 0
        state.cursorCol = 0

        jumpWordForward(state: state)
        #expect(state.cursorCol == 8)
    }

    @Test("Word jump backward moves to previous token start")
    func jumpBackward() {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        state.fileContent = ["alpha   beta"]
        state.cursorRow = 0
        state.cursorCol = 12

        jumpWordBackward(state: state)
        #expect(state.cursorCol == 8)
    }

    @Test("ensureEditorVisible updates horizontal scroll")
    func ensureHorizontalVisible() {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        state.fileContent = ["0123456789abcdefghijklmnopqrstuvwxyz"]
        state.cursorRow = 0
        state.cursorCol = 25
        state.hScrollOffset = 0
        state.config.wrapLines = false

        ensureEditorVisible(state, contentRows: 10, availWidth: 8)
        #expect(state.hScrollOffset > 0)
        #expect(state.hScrollOffset == 18)
    }

    @Test("ensureTreeVisible scrolls selected row into viewport")
    func ensureTreeVisibleScrollsSelection() {
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

    @Test("scrollLinesPerTick scales with viewport height")
    func scrollLinesPerTickScalesWithViewportHeight() {
        #expect(scrollLinesPerTick(visibleRows: 10) == 3)
        #expect(scrollLinesPerTick(visibleRows: 24) == 3)
        #expect(scrollLinesPerTick(visibleRows: 48) == 6)
        #expect(scrollLinesPerTick(visibleRows: 200) == 12)
    }

    @Test("handleEvent moves cursor for repeated arrow keys")
    func handleEventMovesCursorForRepeatedArrowKeys() {
        let sut = makeSUT(fileContent: ["one", "two", "three"])

        let handled = handleEvent(
            event: .key(KeyEvent(keyCode: Key.down.rawValue, eventType: .repeat)),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(handled)
        #expect(sut.state.cursorRow == 1)
    }

    @Test("handleEvent keeps option arrow repeat semantics")
    func handleEventKeepsOptionArrowRepeatSemantics() {
        let sut = makeSUT(fileContent: ["alpha beta gamma"])

        let handled = handleEvent(
            event: .key(KeyEvent(keyCode: Key.right.rawValue, modifiers: .alt, eventType: .repeat)),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(handled)
        #expect(sut.state.cursorCol == 6)
    }

    @Test("handleEvent keeps page navigation working for repeated fn style keys")
    func handleEventKeepsPageNavigationWorkingForRepeatedFnStyleKeys() {
        let sut = makeSUT(fileContent: (0..<100).map(String.init), rows: 12)

        let handled = handleEvent(
            event: .key(KeyEvent(keyCode: Key.pageDown.rawValue, eventType: .repeat)),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(handled)
        #expect(sut.state.cursorRow == 10)
    }

    @Test("handleEvent ignores repeated escape after leaving the editor")
    func handleEventIgnoresRepeatedEscapeAfterLeavingTheEditor() {
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

    @Test("insertText invalidates cached file snapshot")
    func insertTextInvalidatesCachedFileSnapshot() {
        let sut = makeSUT(fileContent: ["hello"])
        _ = sut.state.fileContent
        sut.state.cursorCol = 5

        insertText("!", into: sut.state)

        #expect(sut.state.fileContent == ["hello!"])
        #expect(sut.state.fileLineCount == 1)
    }

    @Test("handleEvent enter invalidates cached file snapshot")
    func handleEventEnterInvalidatesCachedFileSnapshot() {
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

    @Test("handleEvent backspace invalidates cached file snapshot")
    func handleEventBackspaceInvalidatesCachedFileSnapshot() {
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

    @Test("mouse click on wrapped editor row uses shared widget hit testing")
    func handleMouseClickForWrappedLine() {
        let sut = makeSUT(fileContent: ["abcdef"], columns: 11, rows: 6)
        sut.state.config.wrapLines = true
        sut.state.treePanelWidth = 3
        sut.state.mode = .editor

        handleMouse(
            MouseEvent(button: .left, row: 3, col: 9, kind: .press),
            state: sut.state,
            pipeline: sut.pipeline
        )

        #expect(sut.state.cursorRow == 0)
        #expect(sut.state.cursorCol == 4)
    }
}

@Suite("KittyCode Syntax Wiring")
struct KittyCodeSyntaxWiringTests {
    @Test func `language highlighter uses grammar-backed swift highlighting when available`() {
        let lines = LanguageHighlighter.highlightDocument(source: "import Foundation", language: "swift")
        let spans = lines[0]
        let keywordSpan = spans.first { $0.text == "import" }
        #expect(keywordSpan != nil)
        #expect(keywordSpan?.style != Theme.monokai.defaultStyle)
    }

    @Test func `language highlighter uses grammar-backed json highlighting when available`() {
        let lines = LanguageHighlighter.highlightDocument(source: "true", language: "json")
        #expect(lines.count == 1)
        #expect(lines[0].count == 1)
        #expect(lines[0][0].text == "true")
        #expect(lines[0][0].style != Theme.monokai.defaultStyle)
    }

    @Test func `language highlighter falls back for unsupported languages`() {
        let lines = LanguageHighlighter.highlightDocument(source: "// comment", language: "unknown_lang")
        #expect(lines.count == 1)
        #expect(lines[0].count == 1)
        #expect(lines[0][0].text == "// comment")
    }

    @Test("EditorState refreshHighlights populates per-line styled output")
    @MainActor
    func editorStateRefreshHighlights() {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        state.fileContent = ["import Foundation", "let x = 42"]
        state.currentLanguage = "swift"

        state.refreshHighlights()

        #expect(state.highlightedLines.count == 2)
        #expect(!state.highlightedLine(at: 0).isEmpty)
        #expect(!state.highlightedLine(at: 1).isEmpty)
    }

    @Test("EditorState fallback highlighting reuses line-based input for unsupported languages")
    @MainActor
    func editorStateRefreshHighlightsForFallbackLanguage() {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        state.fileContent = ["// comment", "value"]
        state.currentLanguage = "unknown_lang"

        state.refreshHighlights()

        #expect(state.highlightedLines.count == 2)
        #expect(state.highlightedLines[0].map(\.text).joined() == "// comment")
        #expect(state.highlightedLines[1].map(\.text).joined() == "value")
    }

    @Test("EditorState patches only the affected fallback highlight range")
    @MainActor
    func editorStateIncrementalFallbackHighlighting() {
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

        let mutation = TextOperations.deleteBackward(in: &state.textBuffer, at: &state.textCursor)
        #expect(mutation != nil)
        if let mutation {
            state.textDidChange(mutation)
        }

        #expect(state.fileContent == ["helloworld", "tail"])
        #expect(state.highlightedLines.count == 2)
        #expect(state.highlightedLines[0].map(\.text).joined() == "helloworld")
        #expect(state.highlightedLines[1][0].text == "tail-sentinel")
    }
}

// MARK: - detectLanguage tests

@Suite("detectLanguage")
@MainActor
struct DetectLanguageTests {
    @Test func `swift extension maps to swift`() {
        #expect(EditorState.detectLanguage(for: "file.swift") == "swift")
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

import Testing

@testable import KittyCodecs
@testable import KittyRenderer
@testable import KittySyntax
@testable import KittyWidgets

@Suite
struct TextEditorRenderingTests {
    private func makeSUT(columns: Int = 20, rows: Int = 5) -> ScreenBuffer {
        makeTextRenderingBuffer(columns: columns, rows: rows)
    }

    @Test func `render text editor applies current-line background to content and trailing cells`() {
        var buffer = makeSUT(columns: 6, rows: 1)
        let rect = Rect(x: 0, y: 0, width: 6, height: 1)
        let editorStyle = Style(bg: .rgb(r: 10, g: 20, b: 30))
        let currentLineStyle = Style(bg: .rgb(r: 40, g: 50, b: 60))
        let textStyle = Style(fg: .rgb(r: 70, g: 80, b: 90))
        let editor = TextEditor(
            lines: ["Hi"],
            lineSpans: [[StyledSpan(text: "Hi", style: textStyle)]],
            cursorRow: 0,
            showLineNumbers: false,
            wrapLines: false,
            editorStyle: editorStyle,
            currentLineStyle: currentLineStyle
        )

        editor.render(to: &buffer, in: rect)

        #expect(buffer[0, 0].character == "H")
        #expect(buffer[0, 0].style.fg == textStyle.fg)
        #expect(buffer[0, 0].style.bg == currentLineStyle.bg)
        #expect(buffer[0, 2].character == " ")
        #expect(buffer[0, 2].style.bg == currentLineStyle.bg)
    }

    @Test func `render text editor applies current-line style across the full editor width`() {
        var buffer = makeSUT(columns: 8, rows: 1)
        let rect = Rect(x: 0, y: 0, width: 8, height: 1)
        let currentLineStyle = Style(bg: .rgb(r: 40, g: 50, b: 60))
        let editor = TextEditor(
            lines: ["Hi"],
            lineSpans: [[StyledSpan(text: "Hi", style: .default)]],
            cursorRow: 0,
            showLineNumbers: true,
            currentLineStyle: currentLineStyle
        )

        editor.render(to: &buffer, in: rect)

        #expect(buffer[0, 0].style.bg == currentLineStyle.bg)
        #expect(buffer[0, 7].style.bg == currentLineStyle.bg)
    }

    @Test func `render text editor blends line overlays into text and trailing fill`() {
        var buffer = makeSUT(columns: 4, rows: 1)
        let rect = Rect(x: 0, y: 0, width: 4, height: 1)
        let overlay = TextStyleOverlay(
            foreground: ColorOverlay(color: .rgb(r: 220, g: 40, b: 60), alpha: 0.5),
            background: ColorOverlay(color: .rgb(r: 110, g: 120, b: 130), alpha: 0.5)
        )
        let textStyle = Style(
            fg: .rgb(r: 20, g: 40, b: 60),
            bg: .rgb(r: 10, g: 20, b: 30)
        )
        let editor = TextEditor(
            lines: ["A"],
            lineSpans: [[StyledSpan(text: "A", style: textStyle)]],
            showLineNumbers: false,
            lineStyleOverlays: [0: overlay],
            editorStyle: Style(bg: .rgb(r: 10, g: 20, b: 30))
        )

        editor.render(to: &buffer, in: rect)

        #expect(buffer[0, 0].style.fg == .rgb(r: 120, g: 40, b: 60))
        #expect(buffer[0, 0].style.bg == .rgb(r: 60, g: 70, b: 80))
        #expect(buffer[0, 1].style.bg == .rgb(r: 60, g: 70, b: 80))
    }

    @Test func `render wrapped text editor uses line-number gutter only on first visual row`() {
        var buffer = makeSUT(columns: 6, rows: 3)
        let rect = Rect(x: 0, y: 0, width: 6, height: 3)
        let lineNumberStyle = Style(bg: .rgb(r: 1, g: 2, b: 3))
        let editorStyle = Style(bg: .rgb(r: 4, g: 5, b: 6))
        let editor = TextEditor(
            lines: ["abcdef"],
            lineSpans: [[StyledSpan(text: "abcdef", style: .default)]],
            showLineNumbers: true,
            wrapLines: true,
            editorStyle: editorStyle,
            lineNumberStyle: lineNumberStyle
        )

        editor.render(to: &buffer, in: rect)

        #expect(buffer[0, 0].character == " ")
        #expect(buffer[0, 1].character == "1")
        #expect(buffer[0, 2].character == " ")
        #expect(buffer[0, 3].character == "a")
        #expect(buffer[0, 5].character == "c")

        #expect(buffer[1, 0].character == " ")
        #expect(buffer[1, 1].character == " ")
        #expect(buffer[1, 2].character == " ")
        #expect(buffer[1, 0].style.bg == lineNumberStyle.bg)
        #expect(buffer[1, 3].character == "d")
        #expect(buffer[1, 5].character == "f")

        #expect(buffer[2, 0].character == "~")
        #expect(buffer[2, 0].style.bg == lineNumberStyle.bg)
        #expect(buffer[2, 3].character == " ")
        #expect(buffer[2, 3].style.bg == editorStyle.bg)
    }

    @Test func `render wrapped text editor moves tabs to the next visual row when they do not fit`() {
        var buffer = makeSUT(columns: 5, rows: 2)
        let rect = Rect(x: 0, y: 0, width: 5, height: 2)
        let editor = TextEditor(
            lines: ["1234\tX"],
            lineSpans: [[StyledSpan(text: "1234\tX", style: .default)]],
            showLineNumbers: false,
            wrapLines: true,
            tabSize: 4
        )

        editor.render(to: &buffer, in: rect)

        #expect(String((0 ..< 5).map { buffer[0, $0].character }) == "1234 ")
        #expect(String((0 ..< 5).map { buffer[1, $0].character }) == "    X")
    }

    @Test func `cursor layout wraps at tab boundaries instead of splitting the tab`() {
        let editor = TextEditor(
            lines: ["1234\tX"],
            lineSpans: [[StyledSpan(text: "1234\tX", style: .default)]],
            cursorRow: 0,
            cursorCol: 4,
            showLineNumbers: false,
            wrapLines: true,
            tabSize: 4
        )
        let rect = Rect(x: 0, y: 0, width: 5, height: 2)

        let cursor = TextEditorLayout.cursorPosition(for: editor, in: rect)

        #expect(cursor == .init(row: 1, col: 0))
    }

    @Test func `wrapped selected tabs render a glyph and preserve their full span`() {
        var buffer = makeSUT(columns: 6, rows: 1)
        let rect = Rect(x: 0, y: 0, width: 6, height: 1)
        let editor = TextEditor(
            lines: ["\tab"],
            lineSpans: [[StyledSpan(text: "\tab", style: .default)]],
            showLineNumbers: false,
            wrapLines: true,
            highlights: [0: [TextHighlight(range: 0 ... 0, role: .userSelection, style: .default)]],
            tabSize: 4,
            whitespaceConfig: .init(
                showIndentation: false,
                showSpaces: false,
                showLineBreaks: false,
                showUnexpected: false,
                selectionVisibility: .indentation,
                indentationStyle: .default,
                spaceStyle: .default,
                lineBreakStyle: .default,
                unexpectedStyle: .default
            )
        )

        editor.render(to: &buffer, in: rect)

        #expect(String((0 ..< 6).map { buffer[0, $0].character }) == "→   ab")
    }

    @Test func `wrapped emoji occupy two cells so following text stays aligned`() {
        var buffer = makeSUT(columns: 5, rows: 1)
        let rect = Rect(x: 0, y: 0, width: 5, height: 1)
        let editor = TextEditor(
            lines: ["❌ab"],
            lineSpans: [[StyledSpan(text: "❌ab", style: .default)]],
            showLineNumbers: false,
            wrapLines: true
        )

        editor.render(to: &buffer, in: rect)

        #expect(buffer[0, 0].character == "❌")
        #expect(buffer[0, 1].isContinuation)
        #expect(buffer[0, 2].character == "a")
        #expect(buffer[0, 3].character == "b")
    }
}

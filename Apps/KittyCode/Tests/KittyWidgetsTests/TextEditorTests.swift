import Testing

@testable import KittyCodecs
@testable import KittyRenderer
@testable import KittySyntax
@testable import KittyText
@testable import KittyWidgets

@Suite
struct TextEditorTests {
    @Test
    func `Line number width`() {
        let editor = TextEditor(content: "a\nb\nc")
        #expect(editor.lines.count == 3)
        #expect(editor.lineNumberWidth == 1)
    }

    @Test
    func `Gutter width includes decoration column when enabled`() {
        let editor = TextEditor(
            content: "a",
            showsGutterDecorations: true,
            gutterDecorations: [0: .init(symbol: "+", style: .default)]
        )

        #expect(TextEditorLayout.gutterWidth(for: editor) == 5)
    }

    @Test
    func `Cursor layout accounts for line-number gutter and horizontal scroll`() {
        let editor = TextEditor(
            lines: ["abcdef"],
            lineSpans: [[StyledSpan(text: "abcdef", style: .default)]],
            horizontalScrollOffset: 2,
            cursorRow: 0,
            cursorCol: 4,
            showLineNumbers: true,
            wrapLines: false
        )

        let position = TextEditorLayout.cursorPosition(
            for: editor,
            in: Rect(x: 5, y: 3, width: 8, height: 1)
        )

        #expect(position == .init(row: 3, col: 10))
    }

    @Test
    func `Cursor layout accounts for wrapped rows`() {
        let editor = TextEditor(
            lines: ["abcdef"],
            lineSpans: [[StyledSpan(text: "abcdef", style: .default)]],
            cursorRow: 0,
            cursorCol: 4,
            showLineNumbers: true,
            wrapLines: true
        )

        let position = TextEditorLayout.cursorPosition(
            for: editor,
            in: Rect(x: 5, y: 3, width: 6, height: 2)
        )

        #expect(position == .init(row: 4, col: 9))
    }

    @Test
    func `Render text editor writes gutter decoration before line numbers`() {
        var buffer = ScreenBuffer(columns: 12, rows: 1)
        let markerStyle = Style(fg: .rgb(r: 1, g: 2, b: 3))
        let editor = TextEditor(
            lines: ["hello"],
            lineSpans: [[StyledSpan(text: "hello", style: .default)]],
            showLineNumbers: true,
            showsGutterDecorations: true,
            gutterDecorations: [0: .init(symbol: "+", style: markerStyle)]
        )

        editor.render(to: &buffer, in: Rect(x: 0, y: 0, width: 12, height: 1))

        #expect(buffer[0, 0].character == "+")
        #expect(buffer[0, 0].style.fg == markerStyle.fg)
        #expect(buffer[0, 3].character == "1")
    }

    @Test
    func `Wrapped text editor shows gutter decoration only on first visual row`() {
        var buffer = ScreenBuffer(columns: 8, rows: 2)
        let editor = TextEditor(
            lines: ["abcdef"],
            lineSpans: [[StyledSpan(text: "abcdef", style: .default)]],
            showLineNumbers: true,
            showsGutterDecorations: true,
            gutterDecorations: [0: .init(symbol: "~", style: .default)],
            wrapLines: true
        )

        editor.render(to: &buffer, in: Rect(x: 0, y: 0, width: 8, height: 2))

        #expect(buffer[0, 0].character == "~")
        #expect(buffer[1, 0].character == " ")
    }

    @Test
    func
        `Wrapped text editor preserves selection aware whitespace visibility on later visual rows`()
    {
        var buffer = ScreenBuffer(columns: 4, rows: 2)
        let editor = TextEditor(
            lines: ["abcd  "],
            lineSpans: [[StyledSpan(text: "abcd  ", style: .default)]],
            showLineNumbers: false,
            wrapLines: true,
            highlights: [0: [TextHighlight(range: 4 ... 5, role: .userSelection, style: .default)]],
            whitespaceConfig: .init(
                showIndentation: false,
                showSpaces: false,
                showLineBreaks: false,
                showUnexpected: true,
                selectionVisibility: .all,
                indentationStyle: .default,
                spaceStyle: .default,
                lineBreakStyle: .default,
                unexpectedStyle: .default
            )
        )

        editor.render(to: &buffer, in: Rect(x: 0, y: 0, width: 4, height: 2))

        #expect(buffer[1, 0].character == "·")
        #expect(buffer[1, 1].character == "·")
    }

    @Test
    func `wrapped row starts keep tab stops anchored to the logical line`() {
        #expect(
            TextEditorLayout.wrappedRowStartColumns(
                for: "aaaaa\txx",
                contentWidth: 5,
                tabSize: 4
            ) == [0, 5]
        )
    }

    @Test
    func `Hit testing maps clicks into scrolled unwrapped content`() {
        let editor = TextEditor(
            lines: ["abcdef"],
            lineSpans: [[StyledSpan(text: "abcdef", style: .default)]],
            horizontalScrollOffset: 2,
            showLineNumbers: true,
            wrapLines: false
        )

        let position = TextEditorLayout.textPosition(
            for: editor,
            in: Rect(x: 5, y: 3, width: 8, height: 1),
            row: 3,
            col: 10
        )

        #expect(position == .init(row: 0, col: 4))
    }

    @Test
    func `Hit testing maps clicks into wrapped rows`() {
        let editor = TextEditor(
            lines: ["abcdef"],
            lineSpans: [[StyledSpan(text: "abcdef", style: .default)]],
            showLineNumbers: true,
            wrapLines: true
        )

        let position = TextEditorLayout.textPosition(
            for: editor,
            in: Rect(x: 5, y: 3, width: 6, height: 2),
            row: 4,
            col: 9
        )

        #expect(position == .init(row: 0, col: 4))
    }

    @Test
    func `hit testing inside a wrapped tab span stays on the tab character`() {
        let editor = TextEditor(
            lines: ["aaaaa\txx"],
            lineSpans: [[StyledSpan(text: "aaaaa\txx", style: .default)]],
            showLineNumbers: false,
            wrapLines: true,
            tabSize: 4
        )

        let position = TextEditorLayout.textPosition(
            for: editor,
            in: Rect(x: 0, y: 0, width: 5, height: 2),
            row: 1,
            col: 1
        )

        #expect(position == .init(row: 0, col: 5))
    }

    @Test
    func `Scroll indicator geometry reserves content width and ignores indicator hit testing`() {
        // Need more lines than viewport height to trigger scrollbar
        let lines = ["abcdef", "ghijkl", "mnopqr"]
        let editor = TextEditor(
            lines: lines,
            lineSpans: lines.map { [StyledSpan(text: $0, style: .default)] },
            showLineNumbers: true,
            wrapLines: false,
            showsVerticalScrollIndicator: true
        )
        let rect = Rect(x: 5, y: 3, width: 8, height: 1)

        #expect(TextEditorLayout.contentWidth(for: editor, in: rect) == 4)
        #expect(
            TextEditorLayout.verticalScrollIndicatorRect(for: editor, in: rect)
                == Rect(x: 12, y: 3, width: 1, height: 1))
        #expect(TextEditorLayout.textPosition(for: editor, in: rect, row: 3, col: 12) == nil)
    }

    @Test
    func `Scroll indicator hidden when content fits in viewport`() {
        let editor = TextEditor(
            lines: ["abcdef"],
            lineSpans: [[StyledSpan(text: "abcdef", style: .default)]],
            showLineNumbers: true,
            wrapLines: false,
            showsVerticalScrollIndicator: true
        )
        let rect = Rect(x: 5, y: 3, width: 8, height: 5)

        // 1 line in 5-row viewport → not scrollable → full width for content
        #expect(TextEditorLayout.contentWidth(for: editor, in: rect) == 5)
        #expect(TextEditorLayout.verticalScrollIndicatorRect(for: editor, in: rect) == nil)
    }

    @Test
    func `Horizontal scroll metrics reserve space for the end-of-line caret`() {
        let editor = TextEditor(
            lines: ["abcdef"],
            lineSpans: [[StyledSpan(text: "abcdef", style: .default)]],
            showLineNumbers: false,
            wrapLines: false,
            showsHorizontalScrollIndicator: true
        )
        let rect = Rect(x: 0, y: 0, width: 4, height: 1)

        let metrics = TextEditorLayout.horizontalScrollMetrics(
            for: editor,
            in: rect,
            maxLineWidth: 6
        )

        #expect(metrics.contentLength == 7)
        #expect(metrics.maxOffset == 3)
    }

    @Test
    func `Wrapped scroll indicator drag maps visual rows back to line offsets`() {
        let lines = Array(repeating: "abcdef", count: 4)
        let editor = TextEditor(
            lines: lines,
            lineSpans: lines.map { [StyledSpan(text: $0, style: .default)] },
            showLineNumbers: false,
            wrapLines: true,
            showsVerticalScrollIndicator: true
        )
        let rect = Rect(x: 1, y: 1, width: 4, height: 3)

        let gripOffset = TextEditorLayout.scrollGripOffset(for: editor, in: rect, pointerRow: 1)

        #expect(gripOffset == 0)
        #expect(
            TextEditorLayout.scrollOffset(
                for: editor, in: rect, pointerRow: 3, gripOffset: gripOffset ?? 0) == 3)
    }
}

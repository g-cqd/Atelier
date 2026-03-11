import Testing
@testable import KittyWidgets
@testable import KittyCodecs
@testable import KittyRenderer
@testable import KittySyntax

@Suite
struct ViewProtocolTests {
    @Test
    func `Text view creation`() {
        let text = Text("Hello", style: Style(bold: true))
        #expect(text.content == "Hello")
        #expect(text.style.bold)
    }

    @Test
    func `EmptyView creation`() {
        _ = EmptyView()
    }
}

@Suite
struct LayoutTests {
    @Test
    func `VStack creation`() {
        let stack = VStack {
            Text("A")
            Text("B")
        }
        _ = stack
    }

    @Test
    func `HStack creation`() {
        let stack = HStack(spacing: 2) {
            Text("X")
        }
        _ = stack
    }
}

@Suite
struct TreeViewTests {
    @Test
    func `Visible rows flattening`() {
        let child = TreeNode(value: "child")
        let root = TreeNode(value: "root", children: [child], isExpanded: true)
        let tree = TreeView(root: [root], label: { $0 })
        let rows = tree.visibleRows()
        #expect(rows.count == 2)
        #expect(rows[0].depth == 0)
        #expect(rows[1].depth == 1)
    }

    @Test
    func `Collapsed node hides children`() {
        let child = TreeNode(value: "child")
        let root = TreeNode(value: "root", children: [child], isExpanded: false)
        let tree = TreeView(root: [root], label: { $0 })
        let rows = tree.visibleRows()
        #expect(rows.count == 1)
    }

    @Test
    func `Scroll indicator drag maps track rows into tree scroll offsets`() {
        let tree = TreeView(
            root: (0..<20).map { TreeNode(value: "node-\($0)") },
            scrollOffset: 0,
            showsVerticalScrollIndicator: true,
            label: { $0 }
        )
        let rect = Rect(x: 1, y: 1, width: 10, height: 5)

        #expect(TreeViewLayout.contentWidth(for: tree, in: rect) == 9)
        #expect(TreeViewLayout.verticalScrollIndicatorRect(for: tree, in: rect) == Rect(x: 10, y: 1, width: 1, height: 5))

        let gripOffset = TreeViewLayout.scrollGripOffset(for: tree, in: rect, pointerRow: 2)

        #expect(gripOffset == 1)
        #expect(TreeViewLayout.scrollOffset(for: tree, in: rect, pointerRow: 5, gripOffset: gripOffset ?? 0) == 19)
    }

    @Test
    func `Tree scroll indicator hidden when all items fit in viewport`() {
        let tree = TreeView(
            root: (0..<3).map { TreeNode(value: "node-\($0)") },
            scrollOffset: 0,
            showsVerticalScrollIndicator: true,
            label: { $0 }
        )
        let rect = Rect(x: 0, y: 0, width: 10, height: 5)

        // 3 items in 5-row viewport → no scrollbar needed
        #expect(TreeViewLayout.verticalScrollIndicatorRect(for: tree, in: rect) == nil)
        #expect(TreeViewLayout.contentWidth(for: tree, in: rect) == 10)
    }

    @Test
    func `Tree scroll indicator hidden when rendered with fewer items than viewport`() {
        var buffer = ScreenBuffer(columns: 10, rows: 5)
        let tree = TreeView(
            root: (0..<3).map { TreeNode(value: "n\($0)") },
            scrollOffset: 0,
            showsVerticalScrollIndicator: true,
            style: TreeView<String>.TreeViewStyle(
                scrollIndicatorStyle: VerticalScrollIndicatorStyle(
                    trackCharacter: "|",
                    thumbCharacter: "#"
                )
            ),
            label: { $0 }
        )
        let rect = Rect(x: 0, y: 0, width: 10, height: 5)

        tree.render(to: &buffer, in: rect)

        // Last column should NOT have scrollbar characters since 3 items < 5 rows
        for row in 0..<5 {
            #expect(buffer[row, 9].character != "#")
            #expect(buffer[row, 9].character != "|")
        }
    }
}

@Suite
struct StatusBarTests {
    @Test
    func `Render fixed width`() {
        let bar = StatusBar(left: "L", center: "C", right: "R")
        let rendered = bar.render(width: 30)
        #expect(rendered.count == 30)
    }

    @Test
    func `Non positive width returns empty string`() {
        let bar = StatusBar(left: "L", center: "C", right: "R")

        #expect(bar.render(width: 0).isEmpty)
        #expect(bar.render(width: -1).isEmpty)
    }

    @Test
    func `Edge-aligned rendering preserves the trailing segment`() {
        let bar = StatusBar(left: "left side", right: "RIGHT")
        let rendered = bar.render(width: 14)

        #expect(rendered.count == 14)
        #expect(rendered.hasSuffix("RIGHT"))
    }
}

@Suite
struct ViewModifierTests {
    @Test
    func `ModifiedView preserves wrapped content`() {
        let inner = ModifiedView(content: Text("Hello"), modifier: BoldModifier())
        let outer = ModifiedView(content: inner, modifier: ItalicModifier())

        let resolvedInner = outer.modifierContent.resolve(as: ModifiedView<Text, BoldModifier>.self)
        let resolvedText = resolvedInner?.modifierContent.resolve(as: Text.self)

        #expect(resolvedInner != nil)
        #expect(resolvedText?.content == "Hello")
    }
}

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
        #expect(TextEditorLayout.verticalScrollIndicatorRect(for: editor, in: rect) == Rect(x: 12, y: 3, width: 1, height: 1))
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
        #expect(TextEditorLayout.scrollOffset(for: editor, in: rect, pointerRow: 3, gripOffset: gripOffset ?? 0) == 3)
    }
}

// MARK: - Text Rendering Tests

@Suite
struct TextRenderingTests {
    private func makeSUT(columns: Int = 20, rows: Int = 5) -> ScreenBuffer {
        ScreenBuffer(columns: columns, rows: rows)
    }

    @Test func `render writes characters at correct buffer positions`() {
        let view = Text("Hello")
        var buffer = makeSUT()
        let rect = Rect(x: 0, y: 0, width: 20, height: 1)

        view.render(to: &buffer, in: rect)

        #expect(buffer[0, 0].character == "H")
        #expect(buffer[0, 1].character == "e")
        #expect(buffer[0, 2].character == "l")
        #expect(buffer[0, 3].character == "l")
        #expect(buffer[0, 4].character == "o")
    }

    @Test func `render writes to correct row when rect is offset`() {
        let view = Text("AB")
        var buffer = makeSUT()
        let rect = Rect(x: 3, y: 2, width: 10, height: 1)

        view.render(to: &buffer, in: rect)

        #expect(buffer[2, 3].character == "A")
        #expect(buffer[2, 4].character == "B")
        // Cells before the rect should remain empty
        #expect(buffer[2, 2].character == " ")
        #expect(buffer[0, 3].character == " ")
    }

    @Test func `render clips text to rect width`() {
        let view = Text("Hello")
        var buffer = makeSUT()
        let rect = Rect(x: 0, y: 0, width: 3, height: 1)

        view.render(to: &buffer, in: rect)

        #expect(buffer[0, 0].character == "H")
        #expect(buffer[0, 1].character == "e")
        #expect(buffer[0, 2].character == "l")
        // Character at column 3 should be empty — clipped
        #expect(buffer[0, 3].character == " ")
    }

    @Test func `render applies style from Text to buffer cells`() {
        let style = Style(fg: .rgb(r: 255, g: 128, b: 0), bold: true)
        let view = Text("X", style: style)
        var buffer = makeSUT()
        let rect = Rect(x: 0, y: 0, width: 10, height: 1)

        view.render(to: &buffer, in: rect)

        #expect(buffer[0, 0].style.fg == .rgb(r: 255, g: 128, b: 0))
        #expect(buffer[0, 0].style.bold == true)
    }

    @Test func `render into empty rect does not write to buffer`() {
        let view = Text("Hello")
        var buffer = makeSUT()
        let rect = Rect.zero  // isEmpty == true

        view.render(to: &buffer, in: rect)

        // Nothing should have been written — all cells remain empty
        #expect(buffer.cells.allSatisfy { $0 == .empty })
    }

    @Test func `render RenderContext foreground overrides Text style foreground`() {
        let view = Text("Z", style: Style(fg: .rgb(r: 0, g: 0, b: 0)))
        var buffer = makeSUT()
        let rect = Rect(x: 0, y: 0, width: 10, height: 1)
        var context = RenderContext()
        context.foreground = .rgb(r: 255, g: 0, b: 0)

        view.render(to: &buffer, in: rect, context: context)

        #expect(buffer[0, 0].style.fg == .rgb(r: 255, g: 0, b: 0))
    }

    @Test func `render clears trailing cells when plain text shrinks`() {
        var buffer = makeSUT(columns: 10, rows: 1)
        let rect = Rect(x: 0, y: 0, width: 10, height: 1)
        let style = Style(bg: .rgb(r: 12, g: 34, b: 56))

        Text("Longer", style: style).render(to: &buffer, in: rect)
        Text("Hi", style: style).render(to: &buffer, in: rect)

        #expect(buffer[0, 0].character == "H")
        #expect(buffer[0, 1].character == "i")
        #expect(buffer[0, 2].character == " ")
        #expect(buffer[0, 2].style.bg == style.bg)
        #expect(buffer[0, 5].character == " ")
    }

    @Test func `render clears trailing cells when styled text shrinks`() {
        var buffer = makeSUT(columns: 10, rows: 1)
        let rect = Rect(x: 0, y: 0, width: 10, height: 1)
        var context = RenderContext()
        context.background = .rgb(r: 90, g: 80, b: 70)

        StyledTextView([
            StyledTextView.StyledTextSpan(text: "Longer", style: Style(fg: .rgb(r: 255, g: 0, b: 0))),
        ]).render(to: &buffer, in: rect, context: context)

        StyledTextView([
            StyledTextView.StyledTextSpan(text: "Hi", style: Style(fg: .rgb(r: 0, g: 255, b: 0))),
        ]).render(to: &buffer, in: rect, context: context)

        #expect(buffer[0, 0].character == "H")
        #expect(buffer[0, 1].character == "i")
        #expect(buffer[0, 2].character == " ")
        #expect(buffer[0, 2].style.bg == .rgb(r: 90, g: 80, b: 70))
        #expect(buffer[0, 2].style.fg == .default)
    }

    @Test func `render clears trailing cells when selected tree row shrinks`() {
        var buffer = makeSUT(columns: 12, rows: 2)
        let rect = Rect(x: 0, y: 0, width: 12, height: 2)
        let selectedStyle = Style(bg: .rgb(r: 1, g: 2, b: 3))
        let child = TreeNode(value: "child")

        TreeView(
            root: [TreeNode(value: "LongerName", children: [child], isExpanded: false)],
            selectedIndex: 0,
            style: TreeView<String>.TreeViewStyle(
                normalStyle: .default,
                selectedStyle: selectedStyle,
                expandedIcon: "[-]",
                collapsedIcon: "[+]",
                leafIcon: "   ",
                indent: 2
            ),
            label: { $0 }
        ).render(to: &buffer, in: rect)

        TreeView(
            root: [TreeNode(value: "Tests", children: [child], isExpanded: false)],
            selectedIndex: 0,
            style: TreeView<String>.TreeViewStyle(
                normalStyle: .default,
                selectedStyle: selectedStyle,
                expandedIcon: "[-]",
                collapsedIcon: "[+]",
                leafIcon: "   ",
                indent: 2
            ),
            label: { $0 }
        ).render(to: &buffer, in: rect)

        #expect(buffer[0, 0].character == "[")
        #expect(buffer[0, 1].character == "+")
        #expect(buffer[0, 2].character == "]")
        #expect(buffer[0, 3].character == "T")
        #expect(buffer[0, 8].character == " ")
        #expect(buffer[0, 8].style.bg == selectedStyle.bg)
        #expect(buffer[0, 10].character == " ")
    }

    @Test func `render clears stale rows when tree becomes empty`() {
        var buffer = makeSUT(columns: 12, rows: 2)
        let rect = Rect(x: 0, y: 0, width: 12, height: 2)
        let normalStyle = Style(bg: .rgb(r: 11, g: 22, b: 33))

        TreeView(
            root: [TreeNode(value: "Root", isExpanded: false)],
            style: TreeView<String>.TreeViewStyle(
                normalStyle: normalStyle,
                selectedStyle: .default,
                expandedIcon: "[-]",
                collapsedIcon: "[+]",
                leafIcon: "   ",
                indent: 2
            ),
            label: { $0 }
        ).render(to: &buffer, in: rect)

        TreeView(
            root: [],
            style: TreeView<String>.TreeViewStyle(
                normalStyle: normalStyle,
                selectedStyle: .default,
                expandedIcon: "[-]",
                collapsedIcon: "[+]",
                leafIcon: "   ",
                indent: 2
            ),
            label: { $0 }
        ).render(to: &buffer, in: rect)

        #expect(buffer[0, 0].character == " ")
        #expect(buffer[0, 0].style.bg == normalStyle.bg)
        #expect(buffer[1, 11].character == " ")
        #expect(buffer[1, 11].style.bg == normalStyle.bg)
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

        #expect(String((0..<5).map { buffer[0, $0].character }) == "1234 ")
        #expect(String((0..<5).map { buffer[1, $0].character }) == "    X")
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

    @Test func `render tree view draws a vertical scroll indicator when enabled`() {
        var buffer = makeSUT(columns: 8, rows: 4)
        let rect = Rect(x: 0, y: 0, width: 8, height: 4)
        let scrollStyle = VerticalScrollIndicatorStyle(
            trackStyle: Style(fg: .rgb(r: 1, g: 2, b: 3)),
            thumbStyle: Style(fg: .rgb(r: 4, g: 5, b: 6)),
            trackCharacter: "|",
            thumbCharacter: "#"
        )

        TreeView(
            root: (0..<10).map { TreeNode(value: "row-\($0)") },
            showsVerticalScrollIndicator: true,
            style: TreeView<String>.TreeViewStyle(scrollIndicatorStyle: scrollStyle),
            label: { $0 }
        ).render(to: &buffer, in: rect)

        #expect(buffer[0, 7].character == "#")
        #expect(buffer[1, 7].character == "#")
        #expect(buffer[3, 7].character == "|")
    }
}

// MARK: - ScrollView Tests

@Suite
struct ScrollViewTests {
    private func makeSUT(columns: Int = 20, rows: Int = 5) -> ScreenBuffer {
        ScreenBuffer(columns: columns, rows: rows)
    }

    @Test
    func `ScrollView hides scrollbar when content fits in viewport`() {
        let scrollView = ScrollView(contentHeight: 3, scrollOffset: 0) {
            Text("Hello")
        }
        let rect = Rect(x: 0, y: 0, width: 10, height: 5)

        #expect(ScrollViewLayout.scrollIndicatorWidth(for: scrollView, in: rect) == 0)
        #expect(ScrollViewLayout.contentWidth(for: scrollView, in: rect) == 10)
        #expect(ScrollViewLayout.verticalScrollIndicatorRect(for: scrollView, in: rect) == nil)
    }

    @Test
    func `ScrollView shows scrollbar when content overflows viewport`() {
        let scrollView = ScrollView(contentHeight: 20, scrollOffset: 0) {
            Text("Hello")
        }
        let rect = Rect(x: 0, y: 0, width: 10, height: 5)

        #expect(ScrollViewLayout.scrollIndicatorWidth(for: scrollView, in: rect) == 1)
        #expect(ScrollViewLayout.contentWidth(for: scrollView, in: rect) == 9)
        #expect(ScrollViewLayout.verticalScrollIndicatorRect(for: scrollView, in: rect) == Rect(x: 9, y: 0, width: 1, height: 5))
    }

    @Test
    func `ScrollView content rect excludes scrollbar when scrollable`() {
        let scrollView = ScrollView(contentHeight: 20, scrollOffset: 0) {
            Text("Hello")
        }
        let rect = Rect(x: 2, y: 3, width: 10, height: 5)

        let contentRect = ScrollViewLayout.contentRect(for: scrollView, in: rect)
        #expect(contentRect == Rect(x: 2, y: 3, width: 9, height: 5))
    }

    @Test
    func `ScrollView content rect uses full width when content fits`() {
        let scrollView = ScrollView(contentHeight: 3, scrollOffset: 0) {
            Text("Hello")
        }
        let rect = Rect(x: 0, y: 0, width: 10, height: 5)

        let contentRect = ScrollViewLayout.contentRect(for: scrollView, in: rect)
        #expect(contentRect == Rect(x: 0, y: 0, width: 10, height: 5))
    }

    @Test
    func `ScrollView drag maps pointer rows to scroll offsets`() {
        let scrollView = ScrollView(contentHeight: 20, scrollOffset: 0) {
            Text("Hello")
        }
        let rect = Rect(x: 0, y: 0, width: 10, height: 5)

        let gripOffset = ScrollViewLayout.scrollGripOffset(for: scrollView, in: rect, pointerRow: 0)
        #expect(gripOffset == 0)

        let offset = ScrollViewLayout.scrollOffset(
            for: scrollView, in: rect, pointerRow: 4, gripOffset: 0
        )
        #expect(offset == 15)
    }

    @Test
    func `ScrollView clampedOffset respects bounds`() {
        let scrollView = ScrollView(contentHeight: 20, scrollOffset: 0) {
            Text("Hello")
        }
        let rect = Rect(x: 0, y: 0, width: 10, height: 5)

        #expect(ScrollViewLayout.clampedOffset(for: scrollView, in: rect, offset: -5) == 0)
        #expect(ScrollViewLayout.clampedOffset(for: scrollView, in: rect, offset: 100) == 15)
        #expect(ScrollViewLayout.clampedOffset(for: scrollView, in: rect, offset: 10) == 10)
    }

    @Test
    func `ScrollView renders content into full width when content fits`() {
        var buffer = makeSUT(columns: 10, rows: 3)
        let rect = Rect(x: 0, y: 0, width: 10, height: 3)

        ScrollView(contentHeight: 2, scrollOffset: 0) {
            Text("Hello")
        }.render(to: &buffer, in: rect)

        #expect(buffer[0, 0].character == "H")
        #expect(buffer[0, 4].character == "o")
        #expect(buffer[0, 9].character == " ")
    }

    @Test
    func `ScrollView renders scrollbar thumb when content overflows`() {
        let thumbStyle = Style(fg: .rgb(r: 200, g: 200, b: 200))
        let style = ScrollViewStyle(
            thumbStyle: thumbStyle,
            thumbCharacter: "#"
        )
        var buffer = makeSUT(columns: 10, rows: 4)
        let rect = Rect(x: 0, y: 0, width: 10, height: 4)

        ScrollView(contentHeight: 16, scrollOffset: 0, style: style) {
            Text("Hi")
        }.render(to: &buffer, in: rect)

        #expect(buffer[0, 9].character == "#")
        #expect(buffer[0, 9].style.fg == thumbStyle.fg)
    }

    @Test
    func `ScrollView does not render scrollbar column when content fits`() {
        let style = ScrollViewStyle(trackCharacter: "|", thumbCharacter: "#")
        var buffer = makeSUT(columns: 10, rows: 5)
        let rect = Rect(x: 0, y: 0, width: 10, height: 5)

        ScrollView(contentHeight: 3, scrollOffset: 0, style: style) {
            Text("Hi")
        }.render(to: &buffer, in: rect)

        // Last column should not have scrollbar characters
        for row in 0..<5 {
            #expect(buffer[row, 9].character != "#")
            #expect(buffer[row, 9].character != "|")
        }
    }

    @Test
    func `ScrollView default style uses translucent gray`() {
        let style = ScrollViewStyle()
        #expect(style.thumbStyle.dim == true)
        #expect(style.thumbStyle.fg == .rgb(r: 140, g: 140, b: 140))
        #expect(style.thumbCharacter == "\u{2593}") // dark shade
        #expect(style.trackCharacter == " ")
    }

    @Test
    func `ScrollView scroll metrics reports not scrollable when content fits`() {
        let scrollView = ScrollView(contentHeight: 3, scrollOffset: 0) {
            Text("Hello")
        }
        let rect = Rect(x: 0, y: 0, width: 10, height: 5)
        let metrics = ScrollViewLayout.verticalScrollMetrics(for: scrollView, in: rect)

        #expect(!metrics.isScrollable)
    }

    @Test
    func `ScrollView scroll metrics reports scrollable when content overflows`() {
        let scrollView = ScrollView(contentHeight: 20, scrollOffset: 5) {
            Text("Hello")
        }
        let rect = Rect(x: 0, y: 0, width: 10, height: 5)
        let metrics = ScrollViewLayout.verticalScrollMetrics(for: scrollView, in: rect)

        #expect(metrics.isScrollable)
        #expect(metrics.offset == 5)
        #expect(metrics.contentLength == 20)
        #expect(metrics.viewportLength == 5)
    }

    @Test
    func `ScrollView gripOffset returns nil when content fits`() {
        let scrollView = ScrollView(contentHeight: 3, scrollOffset: 0) {
            Text("Hello")
        }
        let rect = Rect(x: 0, y: 0, width: 10, height: 5)

        #expect(ScrollViewLayout.scrollGripOffset(for: scrollView, in: rect, pointerRow: 2) == nil)
    }

    @Test
    func `ScrollViewStyle converts to VerticalScrollIndicatorStyle`() {
        let style = ScrollViewStyle(
            trackStyle: Style(fg: .rgb(r: 10, g: 20, b: 30)),
            thumbStyle: Style(fg: .rgb(r: 40, g: 50, b: 60)),
            trackCharacter: "|",
            thumbCharacter: "#"
        )
        let indicator = style.indicatorStyle

        #expect(indicator.trackStyle.fg == .rgb(r: 10, g: 20, b: 30))
        #expect(indicator.thumbStyle.fg == .rgb(r: 40, g: 50, b: 60))
        #expect(indicator.trackCharacter == "|")
        #expect(indicator.thumbCharacter == "#")
    }
}

// MARK: - ViewModifier Context Tests

@Suite
struct ViewModifierContextTests {
    @Test func `foreground modifier sets foreground on RenderContext`() {
        let modifier = ForegroundModifier(color: .rgb(r: 255, g: 0, b: 0))
        let result = modifier.modifyContext(RenderContext())

        #expect(result.foreground == .rgb(r: 255, g: 0, b: 0))
        #expect(result.background == nil)
        #expect(result.bold == nil)
        #expect(result.italic == nil)
    }

    @Test func `background modifier sets background on RenderContext`() {
        let modifier = BackgroundModifier(color: .rgb(r: 0, g: 0, b: 255))
        let result = modifier.modifyContext(RenderContext())

        #expect(result.background == .rgb(r: 0, g: 0, b: 255))
        #expect(result.foreground == nil)
        #expect(result.bold == nil)
        #expect(result.italic == nil)
    }

    @Test func `bold modifier sets bold on RenderContext`() {
        let modifier = BoldModifier()
        let result = modifier.modifyContext(RenderContext())

        #expect(result.bold == true)
        #expect(result.foreground == nil)
        #expect(result.background == nil)
        #expect(result.italic == nil)
    }

    @Test func `italic modifier sets italic on RenderContext`() {
        let modifier = ItalicModifier()
        let result = modifier.modifyContext(RenderContext())

        #expect(result.italic == true)
        #expect(result.foreground == nil)
        #expect(result.background == nil)
        #expect(result.bold == nil)
    }

    @Test func `chained bold and italic modifiers accumulate on RenderContext`() {
        let base = RenderContext()
        let afterBold = BoldModifier().modifyContext(base)
        let afterBoldAndItalic = ItalicModifier().modifyContext(afterBold)

        #expect(afterBoldAndItalic.bold == true)
        #expect(afterBoldAndItalic.italic == true)
    }

    @Test func `foreground modifier does not clear a previously set bold`() {
        var base = RenderContext()
        base.bold = true
        let result = ForegroundModifier(color: .rgb(r: 100, g: 100, b: 100)).modifyContext(base)

        #expect(result.bold == true)
        #expect(result.foreground == .rgb(r: 100, g: 100, b: 100))
    }
}

// MARK: - RenderContext Tests

@Suite
struct RenderContextTests {
    @Test func `default RenderContext has nil for all properties`() {
        let context = RenderContext()

        #expect(context.foreground == nil)
        #expect(context.background == nil)
        #expect(context.bold == nil)
        #expect(context.italic == nil)
    }

    @Test func `applyTo with no overrides returns the base style unchanged`() {
        let context = RenderContext()
        let base = Style(fg: .rgb(r: 10, g: 20, b: 30), bold: true, italic: true)

        let result = context.applyTo(base)

        #expect(result == base)
    }

    @Test func `applyTo overrides foreground when context foreground is set`() {
        var context = RenderContext()
        context.foreground = .rgb(r: 255, g: 0, b: 0)
        let base = Style(fg: .rgb(r: 0, g: 0, b: 0))

        let result = context.applyTo(base)

        #expect(result.fg == .rgb(r: 255, g: 0, b: 0))
    }

    @Test func `applyTo overrides background when context background is set`() {
        var context = RenderContext()
        context.background = .rgb(r: 0, g: 0, b: 255)
        let base = Style()

        let result = context.applyTo(base)

        #expect(result.bg == .rgb(r: 0, g: 0, b: 255))
    }

    @Test func `applyTo overrides bold when context bold is set`() {
        var context = RenderContext()
        context.bold = true
        let base = Style(bold: false)

        let result = context.applyTo(base)

        #expect(result.bold == true)
    }

    @Test func `applyTo overrides italic when context italic is set`() {
        var context = RenderContext()
        context.italic = true
        let base = Style(italic: false)

        let result = context.applyTo(base)

        #expect(result.italic == true)
    }

    @Test func `merging later context wins for all set properties`() {
        var first = RenderContext()
        first.foreground = .rgb(r: 255, g: 0, b: 0)
        first.bold = true

        var second = RenderContext()
        second.foreground = .rgb(r: 0, g: 255, b: 0)
        second.italic = true

        let merged = first.merging(second)

        #expect(merged.foreground == .rgb(r: 0, g: 255, b: 0))
        #expect(merged.bold == true)
        #expect(merged.italic == true)
        #expect(merged.background == nil)
    }

    @Test func `merging with empty second context preserves first`() {
        var first = RenderContext()
        first.foreground = .rgb(r: 1, g: 2, b: 3)
        first.bold = true

        let merged = first.merging(RenderContext())

        #expect(merged.foreground == .rgb(r: 1, g: 2, b: 3))
        #expect(merged.bold == true)
    }
}

// MARK: - Rect Tests

@Suite
struct RectTests {
    @Test func `zero has all zero components`() {
        let rect = Rect.zero

        #expect(rect.x == 0)
        #expect(rect.y == 0)
        #expect(rect.width == 0)
        #expect(rect.height == 0)
    }

    @Test func `zero is empty`() {
        #expect(Rect.zero.isEmpty)
    }

    @Test func `rect with positive dimensions is not empty`() {
        let rect = Rect(x: 0, y: 0, width: 10, height: 5)
        #expect(!rect.isEmpty)
    }

    @Test func `rect with zero width is empty`() {
        let rect = Rect(x: 0, y: 0, width: 0, height: 5)
        #expect(rect.isEmpty)
    }

    @Test func `rect with zero height is empty`() {
        let rect = Rect(x: 0, y: 0, width: 10, height: 0)
        #expect(rect.isEmpty)
    }

    @Test func `equality holds for identical rects`() {
        let a = Rect(x: 1, y: 2, width: 3, height: 4)
        let b = Rect(x: 1, y: 2, width: 3, height: 4)
        #expect(a == b)
    }

    static let differentRects: [Rect] = [
        Rect(x: 9, y: 2, width: 3, height: 4),
        Rect(x: 1, y: 9, width: 3, height: 4),
        Rect(x: 1, y: 2, width: 9, height: 4),
        Rect(x: 1, y: 2, width: 3, height: 9),
    ]

    @Test(arguments: differentRects)
    func `equality fails when any component differs`(different: Rect) {
        let base = Rect(x: 1, y: 2, width: 3, height: 4)
        #expect(base != different)
    }

    @Test func `maxX equals x plus width`() {
        let rect = Rect(x: 5, y: 0, width: 10, height: 1)
        #expect(rect.maxX == 15)
    }

    @Test func `maxY equals y plus height`() {
        let rect = Rect(x: 0, y: 3, width: 1, height: 7)
        #expect(rect.maxY == 10)
    }
}

// MARK: - FocusEngine Tests

@Suite
struct FocusEngineTests {
    private func makeSUT(focusedIndex: Int = 0, focusableCount: Int = 3) -> FocusEngine {
        FocusEngine(focusedIndex: focusedIndex, focusableCount: focusableCount)
    }

    @Test func `initial focus index is zero by default`() {
        let sut = FocusEngine()
        #expect(sut.focusedIndex == 0)
    }

    @Test func `focusableCount is at least one`() {
        let sut = FocusEngine(focusedIndex: 0, focusableCount: 0)
        #expect(sut.focusableCount == 1)
    }

    @Test func `focusedIndex is at least zero`() {
        let sut = FocusEngine(focusedIndex: -5, focusableCount: 3)
        #expect(sut.focusedIndex == 0)
    }

    @Test func `focusNext increments the focused index`() {
        var sut = makeSUT()
        sut.focusNext()
        #expect(sut.focusedIndex == 1)
    }

    @Test func `focusNext increments through all indices sequentially`() {
        var sut = makeSUT(focusableCount: 3)
        sut.focusNext()
        #expect(sut.focusedIndex == 1)
        sut.focusNext()
        #expect(sut.focusedIndex == 2)
    }

    @Test func `focusNext wraps around from last to first`() {
        var sut = makeSUT(focusedIndex: 2, focusableCount: 3)
        sut.focusNext()
        #expect(sut.focusedIndex == 0)
    }

    @Test func `focusPrevious decrements the focused index`() {
        var sut = makeSUT(focusedIndex: 2, focusableCount: 3)
        sut.focusPrevious()
        #expect(sut.focusedIndex == 1)
    }

    @Test func `focusPrevious decrements through all indices sequentially`() {
        var sut = makeSUT(focusedIndex: 2, focusableCount: 3)
        sut.focusPrevious()
        #expect(sut.focusedIndex == 1)
        sut.focusPrevious()
        #expect(sut.focusedIndex == 0)
    }

    @Test func `focusPrevious wraps around from first to last`() {
        var sut = makeSUT(focusedIndex: 0, focusableCount: 3)
        sut.focusPrevious()
        #expect(sut.focusedIndex == 2)
    }

    @Test func `isFocused returns true for the focused index`() {
        let sut = makeSUT(focusedIndex: 1)
        #expect(sut.isFocused(1))
    }

    @Test func `isFocused returns false for non-focused indices`() {
        let sut = makeSUT(focusedIndex: 1, focusableCount: 3)
        #expect(!sut.isFocused(0))
        #expect(!sut.isFocused(2))
    }

    @Test func `single item focus wraps to itself on focusNext`() {
        var sut = FocusEngine(focusedIndex: 0, focusableCount: 1)
        sut.focusNext()
        #expect(sut.focusedIndex == 0)
    }

    @Test func `single item focus wraps to itself on focusPrevious`() {
        var sut = FocusEngine(focusedIndex: 0, focusableCount: 1)
        sut.focusPrevious()
        #expect(sut.focusedIndex == 0)
    }
}

// MARK: - ListView Tests

@Suite
struct ListViewTests {
    private func makeSUT(columns: Int = 20, rows: Int = 5) -> ScreenBuffer {
        ScreenBuffer(columns: columns, rows: rows)
    }

    @Test func `empty list fills with normal style`() {
        var buffer = makeSUT()
        let list = ListView(items: [], style: ListView.ListViewStyle(normalStyle: Style(fg: .rgb(r: 100, g: 100, b: 100))))
        list.render(to: &buffer, in: Rect(x: 0, y: 0, width: 20, height: 5))
        #expect(buffer[0, 0].character == " ")
        #expect(buffer[0, 0].style.fg == .rgb(r: 100, g: 100, b: 100))
    }

    @Test func `selected item uses selected style`() {
        var buffer = makeSUT()
        let items = [
            ListView.Item(label: "alpha"),
            ListView.Item(label: "beta"),
        ]
        let style = ListView.ListViewStyle(
            normalStyle: Style(fg: .rgb(r: 100, g: 100, b: 100)),
            selectedStyle: Style(fg: .rgb(r: 255, g: 255, b: 255), bold: true)
        )
        let list = ListView(items: items, selectedIndex: 1, style: style)
        list.render(to: &buffer, in: Rect(x: 0, y: 0, width: 20, height: 5))
        // Row 1 (beta) should be bold
        #expect(buffer[1, 1].style.bold == true)
        // Row 0 (alpha) should not be bold
        #expect(buffer[0, 1].style.bold == false)
    }

    @Test func `dirty indicator appears for dirty items`() {
        var buffer = makeSUT()
        let items = [ListView.Item(label: "file.txt", isDirty: true)]
        let list = ListView(items: items, style: ListView.ListViewStyle())
        list.render(to: &buffer, in: Rect(x: 0, y: 0, width: 20, height: 5))
        let rowChars = (0..<20).map { buffer[0, $0].character }
        let rowText = String(rowChars)
        #expect(rowText.contains("\u{25CF}"))
    }

    @Test func `suffix renders with suffix style`() {
        var buffer = makeSUT(columns: 30)
        let items = [ListView.Item(label: "file.txt", suffix: "M", suffixStyle: Style(fg: .rgb(r: 255, g: 0, b: 0)))]
        let list = ListView(items: items, style: ListView.ListViewStyle())
        list.render(to: &buffer, in: Rect(x: 0, y: 0, width: 30, height: 5))
        // Find the M character and check its style
        let mCol = (0..<30).first { buffer[0, $0].character == "M" }
        #expect(mCol != nil)
        if let col = mCol {
            #expect(buffer[0, col].style.fg == .rgb(r: 255, g: 0, b: 0))
        }
    }

    @Test func `scroll offset shifts visible items`() {
        var buffer = makeSUT(rows: 2)
        let items = (0..<5).map { ListView.Item(label: "item\($0)") }
        let list = ListView(items: items, selectedIndex: 3, scrollOffset: 2, style: ListView.ListViewStyle())
        list.render(to: &buffer, in: Rect(x: 0, y: 0, width: 20, height: 2))
        let row0Chars = (0..<20).map { buffer[0, $0].character }
        let row0Text = String(row0Chars).trimmingCharacters(in: .whitespaces)
        #expect(row0Text.contains("item2"))
    }

    @Test func `icon renders before label`() {
        var buffer = makeSUT()
        let items = [ListView.Item(label: "test.txt", icon: "F")]
        let list = ListView(items: items, style: ListView.ListViewStyle())
        list.render(to: &buffer, in: Rect(x: 0, y: 0, width: 20, height: 5))
        let rowChars = (0..<20).map { buffer[0, $0].character }
        let rowText = String(rowChars)
        #expect(rowText.contains("F"))
        #expect(rowText.contains("test.txt"))
    }
}

// MARK: - CenteredText Tests

@Suite
struct CenteredTextTests {
    @Test func `text is horizontally centered`() {
        var buffer = ScreenBuffer(columns: 20, rows: 5)
        let centered = CenteredText(
            text: "Hi",
            style: Style(fg: .rgb(r: 100, g: 100, b: 100)),
            backgroundStyle: Style(fg: .rgb(r: 200, g: 200, b: 200))
        )
        centered.render(to: &buffer, in: Rect(x: 0, y: 0, width: 20, height: 5))
        // Text should be on the middle row (row 2 for height 5)
        let midRow = 2
        let rowChars = (0..<20).map { buffer[midRow, $0].character }
        let rowText = String(rowChars).trimmingCharacters(in: .whitespaces)
        #expect(rowText == "Hi")
    }

    @Test func `background rows use background style`() {
        var buffer = ScreenBuffer(columns: 10, rows: 3)
        let centered = CenteredText(
            text: "X",
            style: Style(fg: .rgb(r: 100, g: 100, b: 100)),
            backgroundStyle: Style(fg: .rgb(r: 50, g: 50, b: 50))
        )
        centered.render(to: &buffer, in: Rect(x: 0, y: 0, width: 10, height: 3))
        // Row 0 should use background style (text is on row 1 for height 3)
        #expect(buffer[0, 0].style.fg == .rgb(r: 50, g: 50, b: 50))
    }

    @Test func `text row uses text style`() {
        var buffer = ScreenBuffer(columns: 10, rows: 3)
        let centered = CenteredText(
            text: "X",
            style: Style(fg: .rgb(r: 100, g: 100, b: 100)),
            backgroundStyle: Style(fg: .rgb(r: 50, g: 50, b: 50))
        )
        centered.render(to: &buffer, in: Rect(x: 0, y: 0, width: 10, height: 3))
        // Middle row (1 for height 3) should use text style
        #expect(buffer[1, 0].style.fg == .rgb(r: 100, g: 100, b: 100))
    }

    @Test func `empty rect produces no crash`() {
        var buffer = ScreenBuffer(columns: 10, rows: 10)
        let centered = CenteredText(text: "Hello")
        centered.render(to: &buffer, in: Rect(x: 0, y: 0, width: 0, height: 0))
        // No crash is the assertion
    }
}

// MARK: - State Property Wrapper Tests

@Suite
struct StatePropertyWrapperTests {
    @Test func `wrappedValue stores the initial value`() {
        let state = State(wrappedValue: 42)
        #expect(state.wrappedValue == 42)
    }

    @Test func `wrappedValue stores initial string value`() {
        let state = State(wrappedValue: "hello")
        #expect(state.wrappedValue == "hello")
    }

    @Test func `wrappedValue stores initial bool value`() {
        let state = State(wrappedValue: true)
        #expect(state.wrappedValue == true)
    }

    @Test func `Binding reads through to the source value`() {
        nonisolated(unsafe) var source = 99
        let binding = Binding<Int>(
            get: { source },
            set: { source = $0 }
        )

        #expect(binding.wrappedValue == 99)
    }

    @Test func `Binding writes through to the source`() {
        nonisolated(unsafe) var source = 0
        let binding = Binding<Int>(
            get: { source },
            set: { source = $0 }
        )

        binding.wrappedValue = 42

        #expect(source == 42)
    }

    @Test func `Binding reflects subsequent source changes`() {
        nonisolated(unsafe) var source = 1
        let binding = Binding<Int>(
            get: { source },
            set: { source = $0 }
        )

        source = 7
        #expect(binding.wrappedValue == 7)
    }
}

// MARK: - Tab Ribbon Scroll Tests

@Suite
struct TabRibbonScrollTests {
    @Test func `tabIndex with non-zero scrollOffset skips earlier tabs`() {
        let tabs = (0..<5).map { TabRibbon.Tab(name: "tab\($0)", isDirty: false) }
        let ribbon = TabRibbon(tabs: tabs, activeIndex: 3, scrollOffset: 2)
        // scrollOffset > 0 adds 1 col for the "<" overflow indicator
        // Tab 2 starts at ribbonX + 1, tab 0 and 1 are scrolled out
        #expect(ribbon.tabIndex(atColumn: 1, ribbonX: 0, ribbonWidth: 20) == 2)
        // Column 0 is the overflow indicator, not a tab
        #expect(ribbon.tabIndex(atColumn: 0, ribbonX: 0, ribbonWidth: 20) == nil)
    }

    @Test func `clampedScrollOffset scrolls active tab into view`() {
        let tabs = (0..<10).map { TabRibbon.Tab(name: "tab\($0)", isDirty: false) }
        let ribbon = TabRibbon(tabs: tabs, activeIndex: 8, scrollOffset: 0)
        let offset = ribbon.clampedScrollOffset(activeIndex: 8, ribbonWidth: 30)
        #expect(offset > 0)
    }

    @Test func `clampedScrollOffset scrolls left when active tab is before window`() {
        let tabs = (0..<10).map { TabRibbon.Tab(name: "tab\($0)", isDirty: false) }
        let ribbon = TabRibbon(tabs: tabs, activeIndex: 1, scrollOffset: 5)
        let offset = ribbon.clampedScrollOffset(activeIndex: 1, ribbonWidth: 40)
        #expect(offset <= 1)
    }

    @Test func `tabsExtendBeyond returns true when tabs overflow`() {
        let tabs = (0..<10).map { TabRibbon.Tab(name: "long_tab_name_\($0)", isDirty: false) }
        let ribbon = TabRibbon(tabs: tabs, activeIndex: 0, scrollOffset: 0)
        #expect(ribbon.tabsExtendBeyond(ribbonWidth: 30))
    }

    @Test func `tabsExtendBeyond returns false when tabs fit`() {
        let tabs = [TabRibbon.Tab(name: "a", isDirty: false)]
        let ribbon = TabRibbon(tabs: tabs, activeIndex: 0, scrollOffset: 0)
        #expect(!ribbon.tabsExtendBeyond(ribbonWidth: 30))
    }

    @Test func `tabsExtendBeyond accounts for the left overflow indicator width`() {
        let tabs = [
            TabRibbon.Tab(name: "one", isDirty: false),
            TabRibbon.Tab(name: "two", isDirty: false),
            TabRibbon.Tab(name: "tri", isDirty: false),
        ]
        let ribbon = TabRibbon(tabs: tabs, activeIndex: 1, scrollOffset: 1)

        #expect(ribbon.tabsExtendBeyond(ribbonWidth: 10))
    }

    @Test func `overflow indicators rendered when tabs overflow`() {
        var buffer = ScreenBuffer(columns: 20, rows: 1)
        let tabs = (0..<10).map { TabRibbon.Tab(name: "tab\($0)", isDirty: false) }
        let ribbon = TabRibbon(tabs: tabs, activeIndex: 3, scrollOffset: 2)
        ribbon.render(to: &buffer, in: Rect(x: 0, y: 0, width: 20, height: 1))
        #expect(buffer[0, 0].character == "<")
        #expect(buffer[0, 19].character == ">")
    }

    @Test func `tabIndex ignores the right overflow indicator`() {
        let tabs = (0..<10).map { TabRibbon.Tab(name: "tab\($0)", isDirty: false) }
        let ribbon = TabRibbon(tabs: tabs, activeIndex: 3, scrollOffset: 2)

        #expect(ribbon.tabIndex(atColumn: 19, ribbonX: 0, ribbonWidth: 20) == nil)
    }

    @Test func `preview tab renders in italic style`() {
        var buffer = ScreenBuffer(columns: 20, rows: 1)
        let tabs = [TabRibbon.Tab(name: "preview", isDirty: false, isPreview: true)]
        let ribbon = TabRibbon(tabs: tabs, activeIndex: 0, scrollOffset: 0)
        ribbon.render(to: &buffer, in: Rect(x: 0, y: 0, width: 20, height: 1))
        // First content cell (after space) should be italic
        #expect(buffer[0, 1].style.italic == true)
    }
}

// MARK: - Horizontal Scroll Indicator Tests

@Suite
struct HorizontalScrollIndicatorTests {
    @Test func `thumbRect proportional to viewport vs content`() {
        let metrics = ScrollMetrics(contentLength: 100, viewportLength: 25, offset: 0)
        let rect = Rect(x: 0, y: 0, width: 40, height: 1)
        let thumb = HorizontalScrollIndicatorLayout.thumbRect(for: metrics, in: rect)
        #expect(thumb != nil)
        #expect(thumb!.width == 10) // 40 * 25 / 100 = 10
        #expect(thumb!.x == 0) // offset 0
    }

    @Test func `thumbRect moves with offset`() {
        let metrics = ScrollMetrics(contentLength: 100, viewportLength: 25, offset: 75)
        let rect = Rect(x: 0, y: 0, width: 40, height: 1)
        let thumb = HorizontalScrollIndicatorLayout.thumbRect(for: metrics, in: rect)
        #expect(thumb != nil)
        #expect(thumb!.x == 30) // at max offset, thumb at right edge
    }

    @Test func `gripOffset returns non-nil when pointer is within track`() {
        let metrics = ScrollMetrics(contentLength: 100, viewportLength: 25, offset: 0)
        let rect = Rect(x: 0, y: 0, width: 40, height: 1)
        let grip = HorizontalScrollIndicatorLayout.gripOffset(for: metrics, in: rect, pointerCol: 5)
        #expect(grip != nil)
    }

    @Test func `gripOffset returns nil when pointer is outside track`() {
        let metrics = ScrollMetrics(contentLength: 100, viewportLength: 25, offset: 0)
        let rect = Rect(x: 10, y: 0, width: 40, height: 1)
        let grip = HorizontalScrollIndicatorLayout.gripOffset(for: metrics, in: rect, pointerCol: 5)
        #expect(grip == nil)
    }

    @Test func `offset maps pointer position to scroll offset`() {
        let metrics = ScrollMetrics(contentLength: 100, viewportLength: 25, offset: 0)
        let rect = Rect(x: 0, y: 0, width: 40, height: 1)
        let offset = HorizontalScrollIndicatorLayout.offset(
            for: metrics, in: rect, pointerCol: 30, gripOffset: 0
        )
        #expect(offset == 75)
    }

    @Test func `horizontal scroll indicator needs check respects wrapLines`() {
        let editor = TextEditor(
            lines: ["a very long line that should trigger horizontal scrolling when not wrapped"],
            lineSpans: [[StyledSpan(text: "a very long line that should trigger horizontal scrolling when not wrapped", style: .default)]],
            showLineNumbers: false,
            wrapLines: true,
            showsHorizontalScrollIndicator: true
        )
        let rect = Rect(x: 0, y: 0, width: 20, height: 5)
        #expect(!TextEditorLayout.needsHorizontalScrollIndicator(for: editor, in: rect, maxLineWidth: 80))
    }
}

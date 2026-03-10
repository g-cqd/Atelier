import Testing
@testable import KittyWidgets
@testable import KittyCodecs
@testable import KittyRenderer

@Suite("View Protocol")
struct ViewTests {
    @Test("Text view creation")
    func textView() {
        let text = Text("Hello", style: Style(bold: true))
        #expect(text.content == "Hello")
        #expect(text.style.bold)
    }

    @Test("EmptyView creation")
    func emptyView() {
        _ = EmptyView()
    }
}

@Suite("Layout")
struct LayoutTests {
    @Test("VStack creation")
    func vstackCreation() {
        let stack = VStack {
            Text("A")
            Text("B")
        }
        _ = stack
    }

    @Test("HStack creation")
    func hstackCreation() {
        let stack = HStack(spacing: 2) {
            Text("X")
        }
        _ = stack
    }
}

@Suite("TreeView")
struct TreeViewTests {
    @Test("Visible rows flattening")
    func visibleRows() {
        let child = TreeNode(value: "child")
        let root = TreeNode(value: "root", children: [child], isExpanded: true)
        let tree = TreeView(root: [root], label: { $0 })
        let rows = tree.visibleRows()
        #expect(rows.count == 2)
        #expect(rows[0].depth == 0)
        #expect(rows[1].depth == 1)
    }

    @Test("Collapsed node hides children")
    func collapsed() {
        let child = TreeNode(value: "child")
        let root = TreeNode(value: "root", children: [child], isExpanded: false)
        let tree = TreeView(root: [root], label: { $0 })
        let rows = tree.visibleRows()
        #expect(rows.count == 1)
    }
}

@Suite("StatusBar")
struct StatusBarTests {
    @Test("Render fixed width")
    func renderWidth() {
        let bar = StatusBar(left: "L", center: "C", right: "R")
        let rendered = bar.render(width: 30)
        #expect(rendered.count == 30)
    }

    @Test("Non positive width returns empty string")
    func nonPositiveWidthReturnsEmptyString() {
        let bar = StatusBar(left: "L", center: "C", right: "R")

        #expect(bar.render(width: 0).isEmpty)
        #expect(bar.render(width: -1).isEmpty)
    }
}

@Suite("ViewModifier")
struct ViewModifierTests {
    @Test("ModifiedView preserves wrapped content")
    func modifiedViewPreservesWrappedContent() {
        let inner = ModifiedView(content: Text("Hello"), modifier: BoldModifier())
        let outer = ModifiedView(content: inner, modifier: ItalicModifier())

        let resolvedInner = outer.modifierContent.resolve(as: ModifiedView<Text, BoldModifier>.self)
        let resolvedText = resolvedInner?.modifierContent.resolve(as: Text.self)

        #expect(resolvedInner != nil)
        #expect(resolvedText?.content == "Hello")
    }
}

@Suite("TextEditor")
struct TextEditorTests {
    @Test("Line number width")
    func lineNumberWidth() {
        let editor = TextEditor(content: "a\nb\nc")
        #expect(editor.lines.count == 3)
        #expect(editor.lineNumberWidth == 1)
    }
}

// MARK: - Text Rendering Tests

@Suite("Text Rendering")
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
}

// MARK: - ViewModifier Context Tests

@Suite("ViewModifier Context")
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

@Suite("RenderContext")
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

@Suite("Rect")
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

@Suite("FocusEngine")
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

// MARK: - State Property Wrapper Tests

@Suite("State Property Wrapper")
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

import Testing

@testable import KittyCodecs
@testable import KittyRenderer
@testable import KittySyntax
@testable import KittyWidgets

@Suite
struct TextViewRenderingTests {
    private func makeSUT(columns: Int = 20, rows: Int = 5) -> ScreenBuffer {
        makeTextRenderingBuffer(columns: columns, rows: rows)
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
            StyledTextView.StyledTextSpan(
                text: "Longer", style: Style(fg: .rgb(r: 255, g: 0, b: 0)))
        ])
        .render(to: &buffer, in: rect, context: context)

        StyledTextView([
            StyledTextView.StyledTextSpan(text: "Hi", style: Style(fg: .rgb(r: 0, g: 255, b: 0)))
        ])
        .render(to: &buffer, in: rect, context: context)

        #expect(buffer[0, 0].character == "H")
        #expect(buffer[0, 1].character == "i")
        #expect(buffer[0, 2].character == " ")
        #expect(buffer[0, 2].style.bg == .rgb(r: 90, g: 80, b: 70))
        #expect(buffer[0, 2].style.fg == .default)
    }
}

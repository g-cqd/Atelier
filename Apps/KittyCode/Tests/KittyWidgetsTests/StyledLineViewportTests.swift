import Foundation
import Testing

@testable import KittyCodecs
@testable import KittyRenderer
@testable import KittySyntax
@testable import KittyWidgets

@Suite
struct StyledLineViewportTests {
    private func render(
        _ line: String, width: Int = 6, offset: Int = 0,
        spans: [StyledSpan]? = nil,
        highlights: [TextHighlight]? = nil,
        whitespaceConfig: WhitespaceRenderer.Config = .disabled
    ) -> ScreenBuffer {
        var buffer = ScreenBuffer(columns: width, rows: 1)
        let editor = TextEditor(
            lines: [line],
            lineSpans: [spans ?? [StyledSpan(text: line, style: .default)]],
            horizontalScrollOffset: offset,
            showLineNumbers: false,
            wrapLines: false,
            highlights: highlights.map { [0: $0] } ?? [:],
            whitespaceConfig: whitespaceConfig
        )
        editor.render(to: &buffer, in: Rect(x: 0, y: 0, width: width, height: 1))
        return buffer
    }

    @Test(arguments: [
        ("abc", 0, "abc   "),
        ("abcdef", 0, "abcdef"),
        ("abcdefghi", 0, "abcdef"),
        ("abcdefghi", 2, "cdefgh"),
        ("abcdef", 2, "cdef  "),
        ("abcdefghi", 10, "      ")
    ])
    func `short and long ASCII lines retain each viewport cell`(
        line: String, offset: Int, expected: String
    ) {
        let actual = render(line, offset: offset)
        #expect(actual.cells == ContiguousArray(expected.map { Cell(character: $0) }))
    }

    @Test(arguments: [
        ("abc", 0, "\u{1B}[1;1Habc   "),
        ("abcdefghi", 2, "\u{1B}[1;1Hcdefgh")
    ])
    func `short and scrolled long lines retain exact terminal bytes`(
        line: String, offset: Int, expected: String
    ) {
        let actual = DiffRenderer.renderFull(render(line, offset: offset))
        #expect(Array(actual) == Array(expected.utf8))
    }

    @Test
    func `styled spans keep their styles across the scroll boundary`() {
        let red = Style(fg: .rgb(r: 200, g: 10, b: 20))
        let blue = Style(fg: .rgb(r: 10, g: 20, b: 200))
        let actual = render(
            "abcdefghij", offset: 2,
            spans: [StyledSpan(text: "abcd", style: red), StyledSpan(text: "efghij", style: blue)]
        )
        let expected = ContiguousArray([
            Cell(character: "c", style: red), Cell(character: "d", style: red),
            Cell(character: "e", style: blue), Cell(character: "f", style: blue),
            Cell(character: "g", style: blue), Cell(character: "h", style: blue)
        ])
        #expect(actual.cells == expected)
    }

    @Test(arguments: [
        ("界A", 0, "界\0A   ", [2, 0, 1, 1, 1, 1]),
        ("\u{200B}AB", 0, "AB    ", [1, 1, 1, 1, 1, 1]),
        ("👍🏽X", 0, "👍🏽\0X   ", [2, 0, 1, 1, 1, 1]),
        ("A界BC", 2, "BC    ", [1, 1, 1, 1, 1, 1]),
        ("Q界AB", 1, "界\0AB  ", [2, 0, 1, 1, 1, 1]),
        ("A👍🏽BC", 1, "👍🏽\0BC  ", [2, 0, 1, 1, 1, 1]),
        ("\u{200B}abcdefg", 2, "cdefg ", [1, 1, 1, 1, 1, 1]),
        ("A\u{0301}BC", 0, "A\u{0301}BC   ", [1, 1, 1, 1, 1, 1]),
        ("\u{7F}A\u{85}B\u{0}C", 0, " A BC ", [1, 1, 1, 1, 1, 1]),
        ("A\u{7F}BC", 1, " BC   ", [1, 1, 1, 1, 1, 1])
    ])
    func `Unicode and control characters retain their cells after clipping`(
        line: String, offset: Int, expected: String, widths: [Int]
    ) {
        let actual = render(line, offset: offset)
        #expect(Array(actual.cells.map(\.character)) == Array(expected))
        #expect(Array(actual.cells.map { Int($0.width) }) == widths)
    }

    @Test
    func `a clipped wide character retains the line break marker`() {
        let config = WhitespaceRenderer.Config(
            showIndentation: false, showSpaces: false, showLineBreaks: true,
            showUnexpected: false, indentationStyle: .default, spaceStyle: .default,
            lineBreakStyle: .default, unexpectedStyle: .default
        )
        let actual = render("A界XYZ", width: 2, whitespaceConfig: config)
        #expect(
            actual.cells
                == ContiguousArray([
                    Cell(character: "A"), Cell(character: WhitespaceRenderer.lineBreakGlyph)
                ]))
    }

    @Test
    func `a clipped wide character retains a selected line break marker`() {
        let config = WhitespaceRenderer.Config(
            showIndentation: false, showSpaces: false, showLineBreaks: false,
            showUnexpected: false, selectionVisibility: .boundary,
            indentationStyle: .default, spaceStyle: .default,
            lineBreakStyle: .default, unexpectedStyle: .default
        )
        let selection = TextHighlight(range: 5 ... 5, role: .userSelection, style: .default)
        let actual = render("A界XYZ", width: 2, highlights: [selection], whitespaceConfig: config)
        #expect(
            actual.cells
                == ContiguousArray([
                    Cell(character: "A"), Cell(character: WhitespaceRenderer.lineBreakGlyph)
                ]))
    }

    /// Timing stays opt-in so the default test run has no wall-clock dependency.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GDV_BENCH"] != nil))
    func `render two hundred long styled lines into a narrow viewport`() {
        let line = String(repeating: "abcdefghijklmnopqrstuvwxyz0123456789", count: 569)
        let lines = Array(repeating: line, count: 200)
        let spans = Array(repeating: [StyledSpan(text: line, style: .default)], count: 200)
        let editor = TextEditor(
            lines: lines, lineSpans: LineHighlights(spans), showLineNumbers: false, wrapLines: false
        )
        var buffer = ScreenBuffer(columns: 80, rows: 200)
        let rect = Rect(x: 0, y: 0, width: 80, height: 200)
        let clock = ContinuousClock()
        editor.render(to: &buffer, in: rect)
        var samples: [Duration] = []
        samples.reserveCapacity(7)
        for _ in 0 ..< 7 {
            samples.append(clock.measure { editor.render(to: &buffer, in: rect) })
        }
        samples.sort()
        print("BENCH styled viewport median: \(samples[3]); samples: \(samples)")
        #expect(buffer[0, 0].character == "a")
        #expect(buffer[199, 79].character == "h")
    }
}

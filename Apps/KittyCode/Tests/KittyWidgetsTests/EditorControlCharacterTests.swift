import Testing

@testable import KittyCodecs
@testable import KittyRenderer
@testable import KittySyntax
@testable import KittyWidgets

/// The text editor draws a file's control characters as blank columns instead of sending them, and gives NUL no
/// column, as its cursor layout does.
@Suite
struct EditorControlCharacterTests {
    private func renderedRow(_ line: String, wrapLines: Bool) -> String {
        var buffer = ScreenBuffer(columns: 12, rows: 1)
        let editor = TextEditor(
            lines: [line], lineSpans: [[StyledSpan(text: line, style: .default)]], showLineNumbers: false,
            wrapLines: wrapLines)
        editor.render(to: &buffer, in: Rect(x: 0, y: 0, width: 12, height: 1))
        return String((0 ..< 12).map { buffer[0, $0].character })
    }

    @Test(arguments: [false, true])
    func `the editor draws DEL and C1 controls as blank columns`(wrapLines: Bool) {
        #expect(renderedRow("a\u{7F}b\u{85}c\u{9B}d\u{9D}e", wrapLines: wrapLines) == "a b c d e   ")
    }

    @Test(arguments: [false, true])
    func `the editor gives NUL no column, as its layout does`(wrapLines: Bool) {
        #expect(renderedRow("a\u{0}b", wrapLines: wrapLines) == "ab          ")
    }
}

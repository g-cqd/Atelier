import Testing

@testable import AtelierDiff

/// The line-break contract of `DiffModel.lines(of:)`: only a line feed ends a line, so a lone carriage return is
/// content, and a carriage return directly before the line feed belongs to the break, not to the line. This is the
/// same rule as git, `TextLines`, `DiffRenderer.lineRanges(of:lines:)` and `LineSourceTests`, so the diff, the gutter
/// and the hunk numbers count the same lines. Splitting at a lone carriage return here alone would break that
/// agreement, so it has to change in all of them together.
@Suite
struct DiffModelLineBreakTests {
    private static func lines(of text: String) -> [String] {
        DiffModel.lines(of: text).map(String.init)
    }

    @Test
    func `a text of lone carriage returns is one line, its last carriage return dropped`() {
        #expect(Self.lines(of: "a\rb\rc\r") == ["a\rb\rc"])
    }

    @Test
    func `a lone carriage return inside a line stays in it`() {
        #expect(Self.lines(of: "a\rb\nc\n") == ["a\rb", "c"])
    }

    @Test
    func `a carriage return and line feed together are one break and the carriage return is not in the line`() {
        #expect(Self.lines(of: "a\r\nb\r\n") == ["a", "b"])
    }
}

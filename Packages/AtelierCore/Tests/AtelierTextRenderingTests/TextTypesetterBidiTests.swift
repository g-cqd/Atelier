import Testing

@testable import AtelierTextRendering

/// How `LayoutConfiguration.bidi` shapes a row's paragraph direction (text-renderer.md §3.7), read from the carets
/// `TextTypesetter.layoutSynchronously` reports: `caret[i]` is the x of the boundary before UTF-16 unit `i`.
///
/// The Latin tail of each sample (`= x`) makes the rows tell the two directions apart: under a left-to-right paragraph
/// the leading Hebrew or Arabic run is the leftmost and the tail follows it; under a right-to-left one the tail is the
/// leftmost. A tail of digits would not, since the Unicode Bidirectional Algorithm puts a number after a right-to-left
/// letter on its left under either direction.
@Suite
struct TextTypesetterBidiTests {
    private static let fontName = "Menlo-Regular"
    private static let plainStyle = TextStyle(foreground: .fixed(RGBA(red: 0, green: 0, blue: 0)))

    /// A row that starts with a right-to-left letter, a Latin tail after it, and the UTF-16 units of the letters.
    struct RightToLeftSample: Sendable, CustomTestStringConvertible {
        var name: String
        var text: String
        /// The boundaries around the leading right-to-left letters, `0 ... letterCount`.
        var letterCount: Int
        /// The unit of the Latin `x` at the end of the row.
        var tailIndex: Int
        var testDescription: String { name }
    }

    static let samples = [
        RightToLeftSample(name: "Hebrew", text: "שלום = x", letterCount: 4, tailIndex: 7),
        RightToLeftSample(name: "Arabic", text: "مرحبا = x", letterCount: 5, tailIndex: 8)
    ]

    // MARK: Tests

    @Test(arguments: samples)
    func `a row that starts right to left keeps its leading run at the left under forceLeftToRight`(
        sample: RightToLeftSample
    ) throws {
        let carets = try Self.carets(of: sample.text, bidi: .forceLeftToRight)
        let leadingRun = carets[0 ... sample.letterCount]
        let tail = carets[sample.tailIndex]
        let runEnd = try #require(leadingRun.max())
        #expect(runEnd <= tail, "the \(sample.name) run reaches x = \(runEnd), past the tail at x = \(tail): \(carets)")
    }

    @Test
    func `a right-to-left override keeps the logical order under forceLeftToRight`() throws {
        // "a", U+202E (RIGHT-TO-LEFT OVERRIDE), "b", "c": the override would show "a" then "cb".
        let carets = try Self.carets(of: "a\u{202E}bc", bidi: .forceLeftToRight)
        #expect(carets == carets.sorted(), "the override reordered the row: carets \(carets)")
        #expect(carets[3] > carets[2], "b and c swapped places: carets \(carets)")
    }

    @Test
    func `a bidi control is drawn as a placeholder of the same length under forceLeftToRight`() throws {
        // U+202E is drawn as U+25C2, one UTF-16 unit for one, so the row lays out exactly as the placeholder row does.
        let carets = try Self.carets(of: "a\u{202E}bc", bidi: .forceLeftToRight)
        let placeholder = try Self.carets(of: "a\u{25C2}bc", bidi: .forceLeftToRight)
        #expect(
            carets == placeholder, "the control is not its placeholder: carets \(carets), placeholder \(placeholder)")
    }

    /// Characterization, passes today and after the fix: the default policy leaves the algorithm alone.
    @Test(arguments: samples)
    func `a row that starts right to left lays out right to left under unicodeDefault`(
        sample: RightToLeftSample
    ) throws {
        let carets = try Self.carets(of: sample.text, bidi: .unicodeDefault)
        let leadingRun = carets[0 ... sample.letterCount]
        let tail = carets[sample.tailIndex]
        let runStart = try #require(leadingRun.min())
        #expect(
            tail < runStart, "the tail at x = \(tail) is not left of the \(sample.name) run at \(runStart): \(carets)")
    }

    /// Characterization, passes today and after the fix: under the default policy the override still applies.
    @Test
    func `a right-to-left override reorders its text under unicodeDefault`() throws {
        let carets = try Self.carets(of: "a\u{202E}bc", bidi: .unicodeDefault)
        #expect(carets[3] < carets[2], "the override did not reorder b and c: carets \(carets)")
    }

    // MARK: Helpers

    /// The carets of the only visual line of `text` laid out unwrapped with `bidi`.
    private static func carets(of text: String, bidi: BidiPolicy) throws -> [Float] {
        let styled = StyledText.plain(
            rows: [text], font: FontSpec(postScriptName: fontName, pointSize: 20), plainStyle: plainStyle)
        let configuration = LayoutConfiguration(wrap: .none, lineHeight: 28, bidi: bidi)
        let rows = try TextTypesetter.layoutSynchronously(
            RowIndex(0) ..< RowIndex(1), of: styled, configuration: configuration)
        let line = try #require(rows.first?.lines.first)
        return line.carets
    }
}

import CoreGraphics
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

    /// Characterization: the default policy leaves the algorithm alone (guards against .unicodeDefault being treated as .forceLeftToRight).
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

    /// Characterization: the default policy still lets an override reorder its text (guards against the controls being replaced under .unicodeDefault).
    @Test
    func `a right-to-left override reorders its text under unicodeDefault`() throws {
        let carets = try Self.carets(of: "a\u{202E}bc", bidi: .unicodeDefault)
        #expect(carets[3] < carets[2], "the override did not reorder b and c: carets \(carets)")
    }

    /// Each bidi control the mapping covers, with the placeholder it is drawn as.
    static let controlPlaceholders: [(UInt32, UInt32)] = [
        (0x202A, 0x25B8), (0x202D, 0x25B8), (0x2066, 0x25B8), (0x200E, 0x25B8),
        (0x202B, 0x25C2), (0x202E, 0x25C2), (0x2067, 0x25C2), (0x200F, 0x25C2), (0x061C, 0x25C2),
        (0x2068, 0x2194),
        (0x202C, 0x25A1), (0x2069, 0x25A1)
    ]

    @Test(arguments: controlPlaceholders)
    func `each bidi control becomes its placeholder, one UTF-16 unit for one`(control: UInt32, placeholder: UInt32)
        throws
    {
        let controlScalar = try #require(Unicode.Scalar(control))
        let placeholderScalar = try #require(Unicode.Scalar(placeholder))
        let input = "😀a" + String(Character(controlScalar)) + "b"
        let expected = "😀a" + String(Character(placeholderScalar)) + "b"
        let shown = BidiPlaceholders.replacingControls(in: input)
        #expect(shown == expected, "U+\(String(control, radix: 16)) is drawn as \(shown.unicodeScalars.map(\.value))")
        #expect(shown.utf16.count == input.utf16.count, "the substitution changed the UTF-16 length")
    }

    @Test
    func `a row without a control is returned unchanged`() {
        let row = "a😀b"
        #expect(BidiPlaceholders.replacingControls(in: row) == row)
    }

    @Test
    func `rendering lays a control row out as layout does`() throws {
        let text = StyledText.plain(
            rows: ["a\u{202E}bc"], font: FontSpec(postScriptName: Self.fontName, pointSize: 20),
            plainStyle: Self.plainStyle)
        let configuration = LayoutConfiguration(wrap: .none, lineHeight: 28, bidi: .forceLeftToRight)
        let range = RowIndex(0) ..< RowIndex(1)
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let laid = try TextTypesetter.layoutSynchronously(range, of: text, configuration: configuration)
        let tile = try TextTypesetter.renderSynchronously(
            range, of: text, decorations: [], configuration: configuration, appearance: .light,
            colorSpace: colorSpace, scale: 1)
        #expect(tile.geometry.map { $0.lines.map(\.carets) } == laid.map { $0.lines.map(\.carets) })
    }

    @Test
    func `a wrapped right-to-left row keeps a left-to-right base on every line`() throws {
        let row = "שלום עולם = x + y"
        let text = StyledText.plain(
            rows: [row], font: FontSpec(postScriptName: Self.fontName, pointSize: 20), plainStyle: Self.plainStyle)
        let configuration = LayoutConfiguration(wrap: .columns(4), lineHeight: 28, bidi: .forceLeftToRight)
        let geometry = try TextTypesetter.layoutSynchronously(
            RowIndex(0) ..< RowIndex(1), of: text, configuration: configuration)
        let lines = try #require(geometry.first?.lines)
        try #require(lines.count > 1, "the row should wrap onto several lines")
        var expectedStart = 0
        for line in lines {
            #expect(Int(line.bytes.lowerBound.rawValue) == expectedStart, "a line does not start where the last ended")
            expectedStart = Int(line.bytes.upperBound.rawValue)
        }
        #expect(expectedStart == row.utf8.count, "the lines do not cover the row")
    }

    @Test
    func `a tab advances the same under both policies`() throws {
        let forced = try Self.carets(of: "a\tb", bidi: .forceLeftToRight)
        let unicode = try Self.carets(of: "a\tb", bidi: .unicodeDefault)
        #expect(forced == unicode, "forceLeftToRight \(forced), unicodeDefault \(unicode)")
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

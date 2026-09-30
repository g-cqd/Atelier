import Testing

@testable import AtelierTextRendering

@Suite
struct HeightIndexTests {
    static func text(rows: Int) -> StyledText {
        .plain(
            rows: (0 ..< rows).map { "row \($0)" }, font: FontSpec(pointSize: 12),
            plainStyle: TextStyle(foreground: .fixed(RGBA(red: 0, green: 0, blue: 0))))
    }

    @Test func `every row is exact and one line height tall without wrapping`() {
        let configuration = LayoutConfiguration(wrap: .none, lineHeight: 20)
        let index = HeightIndex(text: Self.text(rows: 100), configuration: configuration, cellAdvance: 8)
        #expect(index.documentHeight == 2_000)
        for row in [0, 50, 99] { #expect(index.isExact(RowIndex(row))) }
        #expect(index.y(of: RowIndex(0)) == 0)
        #expect(index.y(of: RowIndex(10)) == 200)
    }

    @Test func `y and row at y agree after an edit`() {
        var index = HeightIndex(
            text: Self.text(rows: 10), configuration: LayoutConfiguration(wrap: .none, lineHeight: 20),
            cellAdvance: 8)
        let delta = index.setHeight(60, of: RowIndex(3))
        #expect(delta == 40)
        #expect(index.isExact(RowIndex(3)))
        #expect(index.y(of: RowIndex(4)) == 20 * 3 + 60)
        #expect(index.documentHeight == 20 * 9 + 60)
        #expect(index.row(atY: index.y(of: RowIndex(4)) + 1) == RowIndex(4))
        #expect(index.row(atY: 0) == RowIndex(0))
    }

    @Test func `row at y finds the last row for a y past the document`() {
        let index = HeightIndex(
            text: Self.text(rows: 5), configuration: LayoutConfiguration(wrap: .none, lineHeight: 20),
            cellAdvance: 8)
        #expect(index.row(atY: 10_000) == RowIndex(4))
    }

    @Test func `wrapping estimates more than one line for a wide row`() {
        let text = StyledText.plain(
            rows: [String(repeating: "x", count: 200)], font: FontSpec(pointSize: 12),
            plainStyle: TextStyle(foreground: .fixed(RGBA(red: 0, green: 0, blue: 0))))
        let configuration = LayoutConfiguration(wrap: .columns(40), lineHeight: 20)
        let index = HeightIndex(text: text, configuration: configuration, cellAdvance: 8)
        #expect(!index.isExact(RowIndex(0)))
        #expect(index.height(of: RowIndex(0)) == 20 * 5)
    }
}

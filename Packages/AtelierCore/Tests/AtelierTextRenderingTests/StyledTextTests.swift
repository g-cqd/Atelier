import Testing

@testable import AtelierTextRendering

@Suite
struct StyledTextTests {
    static let plainStyle = TextStyle(foreground: .fixed(RGBA(red: 0, green: 0, blue: 0)))

    @Test func `rows keep their own bytes and ascii bit`() {
        let text = StyledText.plain(rows: ["abc", "héllo"], font: FontSpec(pointSize: 12), plainStyle: Self.plainStyle)
        #expect(text.rowCount == 2)
        #expect(Array(text.bytes(ofRow: RowIndex(0))) == Array("abc".utf8))
        #expect(text.isASCII(row: RowIndex(0)))
        #expect(!text.isASCII(row: RowIndex(1)))
    }

    @Test func `row containing a document offset finds the row a byte falls in`() {
        let text = StyledText.plain(
            rows: ["ab", "cde", "f"], font: FontSpec(pointSize: 12), plainStyle: Self.plainStyle)
        #expect(text.row(containingDocumentOffset: 0) == RowIndex(0))
        #expect(text.row(containingDocumentOffset: 2) == RowIndex(1))
        #expect(text.row(containingDocumentOffset: 4) == RowIndex(1))
        #expect(text.row(containingDocumentOffset: 5) == RowIndex(2))
    }
}

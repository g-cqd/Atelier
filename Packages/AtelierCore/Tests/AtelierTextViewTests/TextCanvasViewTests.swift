import AppKit
import AtelierTextRendering
import Testing

@testable import AtelierTextView

@MainActor
@Suite
struct TextCanvasViewTests {
    static let plainStyle = TextStyle(foreground: .fixed(RGBA(red: 0, green: 0, blue: 0)))
    static let font = FontSpec(pointSize: 12)

    @Test func `showing a document sizes the view to its rows, unwrapped`() {
        let canvas = TextCanvasView(configuration: LayoutConfiguration(wrap: .none, lineHeight: 16))
        canvas.setFrameSize(NSSize(width: 400, height: 200))
        let text = StyledText.plain(rows: ["one", "two", "three"], font: Self.font, plainStyle: Self.plainStyle)
        canvas.show(text, keepingAnchor: false)
        #expect(canvas.documentHeight == 48)
    }

    @Test func `forEachRow reports every row intersecting the rect, top to bottom`() {
        let canvas = TextCanvasView(configuration: LayoutConfiguration(wrap: .none, lineHeight: 16))
        canvas.setFrameSize(NSSize(width: 400, height: 200))
        let text = StyledText.plain(
            rows: (0 ..< 10).map { "row \($0)" }, font: Self.font, plainStyle: Self.plainStyle)
        canvas.show(text, keepingAnchor: false)
        var rows: [Int] = []
        canvas.forEachRow(in: CGRect(x: 0, y: 16, width: 400, height: 32)) { row, _, _ in rows.append(row.index) }
        #expect(rows == [1, 2, 3])
    }

    @Test func `frame of row matches its position in the height index`() throws {
        let canvas = TextCanvasView(configuration: LayoutConfiguration(wrap: .none, lineHeight: 16))
        canvas.setFrameSize(NSSize(width: 400, height: 200))
        let text = StyledText.plain(rows: ["a", "b", "c"], font: Self.font, plainStyle: Self.plainStyle)
        canvas.show(text, keepingAnchor: false)
        let (frame, _) = try #require(canvas.frame(ofRow: RowIndex(2)))
        #expect(frame.minY == 32)
        #expect(frame.height == 16)
    }
}

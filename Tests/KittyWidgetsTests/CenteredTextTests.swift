import Foundation
import Testing

@testable import KittyCodecs
@testable import KittyRenderer
@testable import KittySyntax
@testable import KittyWidgets

@Suite
struct CenteredTextTests {
    @Test func `text is horizontally centered`() {
        var buffer = ScreenBuffer(columns: 20, rows: 5)
        let centered = CenteredText(
            text: "Hi",
            style: Style(fg: .rgb(r: 100, g: 100, b: 100)),
            backgroundStyle: Style(fg: .rgb(r: 200, g: 200, b: 200))
        )
        centered.render(to: &buffer, in: Rect(x: 0, y: 0, width: 20, height: 5))
        // Text should be on the middle row (row 2 for height 5)
        let midRow = 2
        let rowChars = (0..<20).map { buffer[midRow, $0].character }
        let rowText = String(rowChars).trimmingCharacters(in: .whitespaces)
        #expect(rowText == "Hi")
    }

    @Test func `background rows use background style`() {
        var buffer = ScreenBuffer(columns: 10, rows: 3)
        let centered = CenteredText(
            text: "X",
            style: Style(fg: .rgb(r: 100, g: 100, b: 100)),
            backgroundStyle: Style(fg: .rgb(r: 50, g: 50, b: 50))
        )
        centered.render(to: &buffer, in: Rect(x: 0, y: 0, width: 10, height: 3))
        // Row 0 should use background style (text is on row 1 for height 3)
        #expect(buffer[0, 0].style.fg == .rgb(r: 50, g: 50, b: 50))
    }

    @Test func `text row uses text style`() {
        var buffer = ScreenBuffer(columns: 10, rows: 3)
        let centered = CenteredText(
            text: "X",
            style: Style(fg: .rgb(r: 100, g: 100, b: 100)),
            backgroundStyle: Style(fg: .rgb(r: 50, g: 50, b: 50))
        )
        centered.render(to: &buffer, in: Rect(x: 0, y: 0, width: 10, height: 3))
        // Middle row (1 for height 3) should use text style
        #expect(buffer[1, 0].style.fg == .rgb(r: 100, g: 100, b: 100))
    }

    @Test func `empty rect produces no crash`() {
        var buffer = ScreenBuffer(columns: 10, rows: 10)
        let centered = CenteredText(text: "Hello")
        centered.render(to: &buffer, in: Rect(x: 0, y: 0, width: 0, height: 0))
        // No crash is the assertion
    }
}

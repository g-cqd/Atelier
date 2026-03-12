import Testing

@testable import KittyCodecs
@testable import KittyRenderer
@testable import KittySyntax
@testable import KittyWidgets

@Suite
struct ListViewTests {
    private func makeSUT(columns: Int = 20, rows: Int = 5) -> ScreenBuffer {
        ScreenBuffer(columns: columns, rows: rows)
    }

    @Test func `empty list fills with normal style`() {
        var buffer = makeSUT()
        let list = ListView(
            items: [],
            style: ListView.ListViewStyle(normalStyle: Style(fg: .rgb(r: 100, g: 100, b: 100))))
        list.render(to: &buffer, in: Rect(x: 0, y: 0, width: 20, height: 5))
        #expect(buffer[0, 0].character == " ")
        #expect(buffer[0, 0].style.fg == .rgb(r: 100, g: 100, b: 100))
    }

    @Test func `selected item uses selected style`() {
        var buffer = makeSUT()
        let items = [
            ListView.Item(label: "alpha"),
            ListView.Item(label: "beta"),
        ]
        let style = ListView.ListViewStyle(
            normalStyle: Style(fg: .rgb(r: 100, g: 100, b: 100)),
            selectedStyle: Style(fg: .rgb(r: 255, g: 255, b: 255), bold: true)
        )
        let list = ListView(items: items, selectedIndex: 1, style: style)
        list.render(to: &buffer, in: Rect(x: 0, y: 0, width: 20, height: 5))
        // Row 1 (beta) should be bold
        #expect(buffer[1, 1].style.bold == true)
        // Row 0 (alpha) should not be bold
        #expect(buffer[0, 1].style.bold == false)
    }

    @Test func `dirty indicator appears for dirty items`() {
        var buffer = makeSUT()
        let items = [ListView.Item(label: "file.txt", isDirty: true)]
        let list = ListView(items: items, style: ListView.ListViewStyle())
        list.render(to: &buffer, in: Rect(x: 0, y: 0, width: 20, height: 5))
        let rowChars = (0..<20).map { buffer[0, $0].character }
        let rowText = String(rowChars)
        #expect(rowText.contains("\u{25CF}"))
    }

    @Test func `suffix renders with suffix style`() {
        var buffer = makeSUT(columns: 30)
        let items = [
            ListView.Item(
                label: "file.txt", suffix: "M", suffixStyle: Style(fg: .rgb(r: 255, g: 0, b: 0)))
        ]
        let list = ListView(items: items, style: ListView.ListViewStyle())
        list.render(to: &buffer, in: Rect(x: 0, y: 0, width: 30, height: 5))
        // Find the M character and check its style
        let mCol = (0..<30).first { buffer[0, $0].character == "M" }
        #expect(mCol != nil)
        if let col = mCol {
            #expect(buffer[0, col].style.fg == .rgb(r: 255, g: 0, b: 0))
        }
    }

    @Test func `scroll offset shifts visible items`() {
        var buffer = makeSUT(rows: 2)
        let items = (0..<5).map { ListView.Item(label: "item\($0)") }
        let list = ListView(
            items: items, selectedIndex: 3, scrollOffset: 2, style: ListView.ListViewStyle())
        list.render(to: &buffer, in: Rect(x: 0, y: 0, width: 20, height: 2))
        let row0Chars = (0..<20).map { buffer[0, $0].character }
        let row0Text = String(row0Chars).trimmingCharacters(in: .whitespaces)
        #expect(row0Text.contains("item2"))
    }

    @Test func `icon renders before label`() {
        var buffer = makeSUT()
        let items = [ListView.Item(label: "test.txt", icon: "F")]
        let list = ListView(items: items, style: ListView.ListViewStyle())
        list.render(to: &buffer, in: Rect(x: 0, y: 0, width: 20, height: 5))
        let rowChars = (0..<20).map { buffer[0, $0].character }
        let rowText = String(rowChars)
        #expect(rowText.contains("F"))
        #expect(rowText.contains("test.txt"))
    }
}

import Testing

@testable import KittyCodecs
@testable import KittyRenderer
@testable import KittySyntax
@testable import KittyWidgets

@Suite
struct ScrollViewTests {
    private func makeSUT(columns: Int = 20, rows: Int = 5) -> ScreenBuffer {
        ScreenBuffer(columns: columns, rows: rows)
    }

    @Test
    func `ScrollView hides scrollbar when content fits in viewport`() {
        let scrollView = ScrollView(contentHeight: 3, scrollOffset: 0) {
            Text("Hello")
        }
        let rect = Rect(x: 0, y: 0, width: 10, height: 5)

        #expect(ScrollViewLayout.scrollIndicatorWidth(for: scrollView, in: rect) == 0)
        #expect(ScrollViewLayout.contentWidth(for: scrollView, in: rect) == 10)
        #expect(ScrollViewLayout.verticalScrollIndicatorRect(for: scrollView, in: rect) == nil)
    }

    @Test
    func `ScrollView shows scrollbar when content overflows viewport`() {
        let scrollView = ScrollView(contentHeight: 20, scrollOffset: 0) {
            Text("Hello")
        }
        let rect = Rect(x: 0, y: 0, width: 10, height: 5)

        #expect(ScrollViewLayout.scrollIndicatorWidth(for: scrollView, in: rect) == 1)
        #expect(ScrollViewLayout.contentWidth(for: scrollView, in: rect) == 9)
        #expect(
            ScrollViewLayout.verticalScrollIndicatorRect(for: scrollView, in: rect)
                == Rect(x: 9, y: 0, width: 1, height: 5))
    }

    @Test
    func `ScrollView content rect excludes scrollbar when scrollable`() {
        let scrollView = ScrollView(contentHeight: 20, scrollOffset: 0) {
            Text("Hello")
        }
        let rect = Rect(x: 2, y: 3, width: 10, height: 5)

        let contentRect = ScrollViewLayout.contentRect(for: scrollView, in: rect)
        #expect(contentRect == Rect(x: 2, y: 3, width: 9, height: 5))
    }

    @Test
    func `ScrollView content rect uses full width when content fits`() {
        let scrollView = ScrollView(contentHeight: 3, scrollOffset: 0) {
            Text("Hello")
        }
        let rect = Rect(x: 0, y: 0, width: 10, height: 5)

        let contentRect = ScrollViewLayout.contentRect(for: scrollView, in: rect)
        #expect(contentRect == Rect(x: 0, y: 0, width: 10, height: 5))
    }

    @Test
    func `ScrollView drag maps pointer rows to scroll offsets`() {
        let scrollView = ScrollView(contentHeight: 20, scrollOffset: 0) {
            Text("Hello")
        }
        let rect = Rect(x: 0, y: 0, width: 10, height: 5)

        let gripOffset = ScrollViewLayout.scrollGripOffset(for: scrollView, in: rect, pointerRow: 0)
        #expect(gripOffset == 0)

        let offset = ScrollViewLayout.scrollOffset(
            for: scrollView, in: rect, pointerRow: 4, gripOffset: 0
        )
        #expect(offset == 15)
    }

    @Test
    func `ScrollView clampedOffset respects bounds`() {
        let scrollView = ScrollView(contentHeight: 20, scrollOffset: 0) {
            Text("Hello")
        }
        let rect = Rect(x: 0, y: 0, width: 10, height: 5)

        #expect(ScrollViewLayout.clampedOffset(for: scrollView, in: rect, offset: -5) == 0)
        #expect(ScrollViewLayout.clampedOffset(for: scrollView, in: rect, offset: 100) == 15)
        #expect(ScrollViewLayout.clampedOffset(for: scrollView, in: rect, offset: 10) == 10)
    }

    @Test
    func `ScrollView renders content into full width when content fits`() {
        var buffer = makeSUT(columns: 10, rows: 3)
        let rect = Rect(x: 0, y: 0, width: 10, height: 3)

        ScrollView(contentHeight: 2, scrollOffset: 0) {
            Text("Hello")
        }
        .render(to: &buffer, in: rect)

        #expect(buffer[0, 0].character == "H")
        #expect(buffer[0, 4].character == "o")
        #expect(buffer[0, 9].character == " ")
    }

    @Test
    func `ScrollView renders scrollbar thumb when content overflows`() {
        let thumbStyle = Style(fg: .rgb(r: 200, g: 200, b: 200))
        let style = ScrollViewStyle(
            thumbStyle: thumbStyle,
            thumbCharacter: "#"
        )
        var buffer = makeSUT(columns: 10, rows: 4)
        let rect = Rect(x: 0, y: 0, width: 10, height: 4)

        ScrollView(contentHeight: 16, scrollOffset: 0, style: style) {
            Text("Hi")
        }
        .render(to: &buffer, in: rect)

        #expect(buffer[0, 9].character == "#")
        #expect(buffer[0, 9].style.fg == thumbStyle.fg)
    }

    @Test
    func `ScrollView does not render scrollbar column when content fits`() {
        let style = ScrollViewStyle(trackCharacter: "|", thumbCharacter: "#")
        var buffer = makeSUT(columns: 10, rows: 5)
        let rect = Rect(x: 0, y: 0, width: 10, height: 5)

        ScrollView(contentHeight: 3, scrollOffset: 0, style: style) {
            Text("Hi")
        }
        .render(to: &buffer, in: rect)

        // Last column should not have scrollbar characters
        for row in 0 ..< 5 {
            #expect(buffer[row, 9].character != "#")
            #expect(buffer[row, 9].character != "|")
        }
    }

    @Test
    func `ScrollView default style uses translucent gray`() {
        let style = ScrollViewStyle()
        #expect(style.thumbStyle.dim == true)
        #expect(style.thumbStyle.fg == .rgb(r: 140, g: 140, b: 140))
        #expect(style.thumbCharacter == "\u{2593}")  // dark shade
        #expect(style.trackCharacter == " ")
    }

    @Test
    func `ScrollView scroll metrics reports not scrollable when content fits`() {
        let scrollView = ScrollView(contentHeight: 3, scrollOffset: 0) {
            Text("Hello")
        }
        let rect = Rect(x: 0, y: 0, width: 10, height: 5)
        let metrics = ScrollViewLayout.verticalScrollMetrics(for: scrollView, in: rect)

        #expect(!metrics.isScrollable)
    }

    @Test
    func `ScrollView scroll metrics reports scrollable when content overflows`() {
        let scrollView = ScrollView(contentHeight: 20, scrollOffset: 5) {
            Text("Hello")
        }
        let rect = Rect(x: 0, y: 0, width: 10, height: 5)
        let metrics = ScrollViewLayout.verticalScrollMetrics(for: scrollView, in: rect)

        #expect(metrics.isScrollable)
        #expect(metrics.offset == 5)
        #expect(metrics.contentLength == 20)
        #expect(metrics.viewportLength == 5)
    }

    @Test
    func `ScrollView gripOffset returns nil when content fits`() {
        let scrollView = ScrollView(contentHeight: 3, scrollOffset: 0) {
            Text("Hello")
        }
        let rect = Rect(x: 0, y: 0, width: 10, height: 5)

        #expect(ScrollViewLayout.scrollGripOffset(for: scrollView, in: rect, pointerRow: 2) == nil)
    }

    @Test
    func `ScrollViewStyle converts to VerticalScrollIndicatorStyle`() {
        let style = ScrollViewStyle(
            trackStyle: Style(fg: .rgb(r: 10, g: 20, b: 30)),
            thumbStyle: Style(fg: .rgb(r: 40, g: 50, b: 60)),
            trackCharacter: "|",
            thumbCharacter: "#"
        )
        let indicator = style.indicatorStyle

        #expect(indicator.trackStyle.fg == .rgb(r: 10, g: 20, b: 30))
        #expect(indicator.thumbStyle.fg == .rgb(r: 40, g: 50, b: 60))
        #expect(indicator.trackCharacter == "|")
        #expect(indicator.thumbCharacter == "#")
    }
}

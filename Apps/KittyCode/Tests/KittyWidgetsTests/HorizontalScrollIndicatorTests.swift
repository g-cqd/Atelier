import Testing

@testable import KittyCodecs
@testable import KittyRenderer
@testable import KittySyntax
@testable import KittyWidgets

@Suite
struct HorizontalScrollIndicatorTests {
    @Test func `thumbRect proportional to viewport vs content`() throws {
        let metrics = ScrollMetrics(contentLength: 100, viewportLength: 25, offset: 0)
        let rect = Rect(x: 0, y: 0, width: 40, height: 1)
        let thumb = try #require(HorizontalScrollIndicatorLayout.thumbRect(for: metrics, in: rect))
        #expect(thumb.width == 10)  // 40 * 25 / 100 = 10
        #expect(thumb.x == 0)  // offset 0
    }

    @Test func `thumbRect moves with offset`() throws {
        let metrics = ScrollMetrics(contentLength: 100, viewportLength: 25, offset: 75)
        let rect = Rect(x: 0, y: 0, width: 40, height: 1)
        let thumb = try #require(HorizontalScrollIndicatorLayout.thumbRect(for: metrics, in: rect))
        #expect(thumb.x == 30)  // at max offset, thumb at right edge
    }

    @Test func `gripOffset returns non-nil when pointer is within track`() {
        let metrics = ScrollMetrics(contentLength: 100, viewportLength: 25, offset: 0)
        let rect = Rect(x: 0, y: 0, width: 40, height: 1)
        let grip = HorizontalScrollIndicatorLayout.gripOffset(for: metrics, in: rect, pointerCol: 5)
        #expect(grip != nil)
    }

    @Test func `gripOffset returns nil when pointer is outside track`() {
        let metrics = ScrollMetrics(contentLength: 100, viewportLength: 25, offset: 0)
        let rect = Rect(x: 10, y: 0, width: 40, height: 1)
        let grip = HorizontalScrollIndicatorLayout.gripOffset(for: metrics, in: rect, pointerCol: 5)
        #expect(grip == nil)
    }

    @Test func `offset maps pointer position to scroll offset`() {
        let metrics = ScrollMetrics(contentLength: 100, viewportLength: 25, offset: 0)
        let rect = Rect(x: 0, y: 0, width: 40, height: 1)
        let offset = HorizontalScrollIndicatorLayout.offset(
            for: metrics, in: rect, pointerCol: 30, gripOffset: 0
        )
        #expect(offset == 75)
    }

    @Test func `horizontal scroll indicator needs check respects wrapLines`() {
        let editor = TextEditor(
            lines: ["a very long line that should trigger horizontal scrolling when not wrapped"],
            lineSpans: [
                [
                    StyledSpan(
                        text:
                            "a very long line that should trigger horizontal scrolling when not wrapped",
                        style: .default)
                ]
            ],
            showLineNumbers: false,
            wrapLines: true,
            showsHorizontalScrollIndicator: true
        )
        let rect = Rect(x: 0, y: 0, width: 20, height: 5)
        #expect(
            !TextEditorLayout.needsHorizontalScrollIndicator(
                for: editor, in: rect, maxLineWidth: 80))
    }
}

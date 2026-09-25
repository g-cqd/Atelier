import AppKit
import DiffCore
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// Hosts a `RenderedText` in an off-screen text view configured the same way `DiffTextView.makeNSView` sets one
/// up (TextKit 2, the pane's container inset and padding, no wrapping) and lays it out fully.
@MainActor
private func makeTextView(rendered: RenderedText, width: CGFloat = 800) -> NSTextView {
    let textView = NSTextView(usingTextLayoutManager: true)
    textView.textContainerInset = NSSize(width: 0, height: DiffPaneMetrics.containerInset)
    textView.textContainer?.lineFragmentPadding = DiffPaneMetrics.lineFragmentPadding
    textView.textContainer?.widthTracksTextView = false
    textView.textContainer?.size = NSSize(width: width, height: DiffPaneMetrics.unboundedExtent)
    textView.textContentStorage?.textStorage?.setAttributedString(rendered.attributed)
    textView.textLayoutManager?.ensureLayout(for: textView.textLayoutManager!.documentRange)
    return textView
}

/// The pixel a test wants to click, computed the same way the monospaced system palette lays rows out: uniform
/// row height and character width, the container inset, the line fragment padding, and the bands of the gaps
/// between the rows above as the only offsets.
@MainActor
private func point(row: Int, column: Int, in rendered: RenderedText, centered: Bool = true) -> NSPoint {
    let charWidth = ("0" as NSString).size(withAttributes: [.font: rendered.palette.font]).width
    let x =
        DiffPaneMetrics.lineFragmentPadding + CGFloat(column) * charWidth + (centered ? charWidth / 2 : 0)
    let bands = (0 ..< row).reduce(0) { $0 + rendered.bandSpacing(afterRow: $1) }
    let y = DiffPaneMetrics.containerInset + (CGFloat(row) + 0.5) * rendered.lineHeight + bands
    return NSPoint(x: x, y: y)
}

@MainActor
@Suite(.mainActorLane)
struct HoverHitTesterTests {
    private let text = "let alphaBeta = 1\n"

    private func rendered() throws -> RenderedText {
        try #require(DiffRenderer.render(oldText: text, newText: text, language: .plain).new)
    }

    @Test
    func `a point mid-identifier resolves the row, side, line and column, with an anchor around the point`() throws {
        let rendered = try rendered()
        let textView = makeTextView(rendered: rendered)
        // "let alphaBeta = 1": alphaBeta spans columns 4..<13; column 8 sits inside it.
        let target = point(row: 0, column: 8, in: rendered)

        let hit = try #require(HoverHitTester.hit(at: target, textView: textView, rendered: rendered))

        #expect(hit.row == 0)
        #expect(hit.side == .new)
        #expect(hit.line == 0)
        #expect(hit.utf16Column == 8)
        #expect(hit.fileIndex == 0)
        #expect(hit.anchorRect.minX <= target.x)
        #expect(hit.anchorRect.maxX >= target.x)
    }

    @Test
    func `the first character of an identifier resolves too`() throws {
        let rendered = try rendered()
        let textView = makeTextView(rendered: rendered)
        let target = point(row: 0, column: 4, in: rendered)

        let hit = try #require(HoverHitTester.hit(at: target, textView: textView, rendered: rendered))

        #expect(hit.utf16Column == 4)
    }

    @Test
    func `a point over punctuation or whitespace misses`() throws {
        let rendered = try rendered()
        let textView = makeTextView(rendered: rendered)

        // Column 14 is the '=' sign; column 3 is the space before "alphaBeta".
        #expect(
            HoverHitTester.hit(at: point(row: 0, column: 14, in: rendered), textView: textView, rendered: rendered)
                == nil)
        #expect(
            HoverHitTester.hit(at: point(row: 0, column: 3, in: rendered), textView: textView, rendered: rendered)
                == nil)
    }

    @Test
    func `a point past the end of the line misses`() throws {
        let rendered = try rendered()
        let textView = makeTextView(rendered: rendered)

        #expect(
            HoverHitTester.hit(at: point(row: 0, column: 100, in: rendered), textView: textView, rendered: rendered)
                == nil)
    }

    @Test
    func `a header row misses`() throws {
        let file = FileDiffInput(title: "a.swift", oldText: text, newText: text, language: .plain)
        let prepared = PreparedDiff(file, granularity: .word)
        let diff = DiffRenderer.render(
            prepared: [prepared], options: DiffRenderer.Options(sides: [.new]), layout: .full, withHeaders: true)
        let rendered = try #require(diff.new)
        let textView = makeTextView(rendered: rendered)

        // Row 0 is the header; row 1 is "let alphaBeta = 1".
        #expect(
            HoverHitTester.hit(at: point(row: 0, column: 2, in: rendered), textView: textView, rendered: rendered)
                == nil)
        let hit = HoverHitTester.hit(at: point(row: 1, column: 8, in: rendered), textView: textView, rendered: rendered)
        #expect(hit?.utf16Column == 8)
    }

    @Test
    func `rows after hidden runs hover as their own lines`() throws {
        // Seven lines with the second and sixth edited: with zero context the untouched runs around and between the
        // two changes are hidden, and take no row.
        let old = "line1\nline2AAAA\nline3\nline4\nline5\nline6AAAA\nline7\n"
        let new = "line1\nline2BBBB\nline3\nline4\nline5\nline6BBBB\nline7\n"
        let diff = DiffRenderer.render(
            oldText: old, newText: new, language: .plain, layout: .changes(context: 0, expansions: [:]))
        let rendered = try #require(diff.new)
        let textView = makeTextView(rendered: rendered)

        let first = HoverHitTester.hit(
            at: point(row: 0, column: 2, in: rendered), textView: textView, rendered: rendered)
        let second = HoverHitTester.hit(
            at: point(row: 1, column: 2, in: rendered), textView: textView, rendered: rendered)

        #expect(first?.line == 1)
        #expect(second?.line == 5)
    }

    // MARK: Cards-mode hosting (EmbeddedDiffTextView's real text stack)

    /// Hosts `rendered` the way a card pane does: the text view's layout manager attached to a `StaticTextLayout`'s
    /// detached storage, laid out fully off screen.
    @MainActor
    private func makeCardHostedTextView(rendered: RenderedText, width: CGFloat = 800) -> NSTextView {
        let layout = StaticTextLayout(rendered: rendered)
        layout.layOut(mode: .none, viewportWidth: width)
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.textContainerInset = NSSize(width: 0, height: DiffPaneMetrics.containerInset)
        textView.textContainer?.lineFragmentPadding = DiffPaneMetrics.lineFragmentPadding
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.size = NSSize(width: width, height: DiffPaneMetrics.unboundedExtent)
        let coordinator = EmbeddedDiffTextView.Coordinator()
        coordinator.textView = textView
        coordinator.attach(layout)
        textView.textLayoutManager?.ensureLayout(for: textView.textLayoutManager!.documentRange)
        return textView
    }

    @Test
    func `a card pane's hosted text view resolves a mid-identifier hit the same way a scrolling pane does`() throws {
        let rendered = try rendered()
        let textView = makeCardHostedTextView(rendered: rendered)
        let target = point(row: 0, column: 8, in: rendered)

        let hit = try #require(HoverHitTester.hit(at: target, textView: textView, rendered: rendered))

        #expect(hit.row == 0)
        #expect(hit.side == .new)
        #expect(hit.utf16Column == 8)
        #expect(hit.fileIndex == 0)
    }

    @Test
    func `a card pane's hosted text view rejects a point over punctuation the same way a scrolling pane does`()
        throws
    {
        let rendered = try rendered()
        let textView = makeCardHostedTextView(rendered: rendered)

        // Column 14 is the '=' sign in "let alphaBeta = 1".
        #expect(
            HoverHitTester.hit(at: point(row: 0, column: 14, in: rendered), textView: textView, rendered: rendered)
                == nil)
    }

    // MARK: identifierRange / anchorRect(for:textView:)

    @Test
    func `identifierRange spans the hovered identifier, document-absolute`() throws {
        let rendered = try rendered()
        let textView = makeTextView(rendered: rendered)
        let target = point(row: 0, column: 8, in: rendered)

        let hit = try #require(HoverHitTester.hit(at: target, textView: textView, rendered: rendered))

        let string = rendered.attributed.string as NSString
        #expect(string.substring(with: hit.identifierRange) == "alphaBeta")
    }

    @Test
    func `anchorRect(for:textView:) recomputes the same rect a fresh hit measured`() throws {
        let rendered = try rendered()
        let textView = makeTextView(rendered: rendered)
        let target = point(row: 0, column: 8, in: rendered)
        let hit = try #require(HoverHitTester.hit(at: target, textView: textView, rendered: rendered))

        let recomputed = try #require(HoverHitTester.anchorRect(for: hit.identifierRange, textView: textView))

        #expect(recomputed == hit.anchorRect)
    }

    @Test
    func `anchorRect(for:textView:) is nil for a range past the end of the document`() throws {
        let rendered = try rendered()
        let textView = makeTextView(rendered: rendered)
        let outOfBounds = NSRange(location: rendered.attributed.length + 50, length: 4)

        #expect(HoverHitTester.anchorRect(for: outOfBounds, textView: textView) == nil)
    }

    @Test
    func `an identifier after an emoji keeps a correct UTF-16 column`() throws {
        let line = "let x = \u{1F600} name\n"
        let diff = DiffRenderer.render(oldText: line, newText: line, language: .plain)
        let rendered = try #require(diff.new)
        let textView = makeTextView(rendered: rendered)
        // "let x = 😀 name": 😀 is a surrogate pair at columns 8-9 (2 UTF-16 units); "name" starts at column 11.
        let nsLine = line as NSString
        let nameColumn = (nsLine.range(of: "name")).location
        let target = point(row: 0, column: nameColumn + 1, in: rendered)

        let hit = try #require(HoverHitTester.hit(at: target, textView: textView, rendered: rendered))

        #expect(hit.utf16Column == nameColumn + 1)
    }
}

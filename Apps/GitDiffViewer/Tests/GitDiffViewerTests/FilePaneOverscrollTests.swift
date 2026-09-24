import AppKit
import DiffCore
import SwiftUI
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// A file pane scrolled to its end shows its last line whole, at the top of the pane.
@MainActor
struct FilePaneOverscrollTests {
    private let paneHeight: CGFloat = 300

    private func makeSUT(wrapsLines: Bool) throws -> (textView: NSTextView, clip: NSClipView, text: RenderedText) {
        let lines = (1 ... 40).map { "let value\($0) = \($0)\n" }.joined()
        let text = try #require(
            DiffRenderer.render(oldText: lines, newText: lines, language: .plain, lineHeightMultiple: 1.2).unified)
        let scrollView = NSTextView.scrollableTextView()
        scrollView.frame = NSRect(x: 0, y: 0, width: 400, height: paneHeight)
        let textView = try #require(scrollView.documentView as? NSTextView)
        textView.textContainerInset = NSSize(width: 0, height: DiffPaneMetrics.containerInset)
        let sut = DiffTextViewCoordinator()
        sut.textView = textView
        sut.wrapsLines = wrapsLines
        DiffTextViewCoordinator.configureWrapping(
            wrapsLines, column: 0, font: text.palette.font, textView: textView, scrollView: scrollView)
        sut.apply(text)
        // Laid out whole, as scrolling to the end lays it out, so a wrapped pane's size is final.
        let layoutManager = try #require(textView.textLayoutManager)
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        sut.updateOverscroll(in: scrollView.contentView)
        return (textView, scrollView.contentView, text)
    }

    @Test(arguments: [false, true])
    func `scrolled to its end, a file pane shows its last line whole at its top`(wrapsLines: Bool) throws {
        let sut = try makeSUT(wrapsLines: wrapsLines)
        let lastLineTop =
            DiffPaneMetrics.containerInset + CGFloat(sut.text.rows.count - 1) * sut.text.lineHeight
        let endOffset = sut.textView.frame.height - sut.clip.bounds.height
        #expect(lastLineTop >= endOffset)
        #expect(lastLineTop - endOffset < 1)
    }

    /// `count` lines; every seventh is long enough that TextKit, estimating it before laying it out, takes it for
    /// two lines.
    private static func longLines(_ count: Int) throws -> RenderedText {
        let tail = String(repeating: "long ", count: 32)
        let text =
            (1 ... count)
            .map { $0.isMultiple(of: 7) ? "let value\($0) = \(tail)" : "let value\($0) = \($0)" }
            .joined(separator: "\n") + "\n"
        return try #require(DiffRenderer.render(oldText: text, newText: text, language: .plain).unified)
    }

    @Test
    func `scrolled to its end, a file pane that never wraps shows its last line, though it laid out none above`()
        throws
    {
        let text = try Self.longLines(300)
        let sut = HostedFilePane(showing: text)

        sut.scrollToEnd()

        let lastTop = try #require(sut.shownRows()[text.rows.count - 1])
        #expect(lastTop + text.lineHeight <= sut.visibleRect.maxY)
    }

    @Test
    func `a file pane that never wraps keeps its last line in reach when it grows while scrolled`() throws {
        let sut = HostedFilePane(showing: try Self.longLines(300))
        sut.scroll(to: 2_000)

        let grown = try Self.longLines(600)
        sut.show(grown)
        sut.scrollToEnd()

        let lastTop = try #require(sut.shownRows()[grown.rows.count - 1])
        #expect(lastTop + grown.lineHeight <= sut.visibleRect.maxY)
    }
}

/// A ``DiffTextView`` that never wraps, hosted as the app hosts it, in a borderless window that is never ordered in:
/// TextKit lays out only what shows of it.
@MainActor
private final class HostedFilePane {
    private let window: NSWindow
    private let host: NSHostingView<DiffTextView>

    init(showing rendered: RenderedText) {
        host = NSHostingView(rootView: Self.pane(rendered, keepingScroll: false))
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 300), styleMask: [.borderless], backing: .buffered,
            defer: false)
        window.contentView = host
        settle()
    }

    private static func pane(_ rendered: RenderedText, keepingScroll: Bool) -> DiffTextView {
        DiffTextView(rendered: rendered, gutter: .dual, keepsScrollPosition: keepingScroll, wrapsLines: false)
    }

    private var textView: NSTextView? { Self.first(NSTextView.self, in: host) }
    private var clipView: NSClipView? { textView?.enclosingScrollView?.contentView }
    /// What shows of the text, in the text view.
    var visibleRect: NSRect { textView?.visibleRect ?? .zero }

    /// Shows a new render of the same file, as a reload does, keeping the scroll position.
    func show(_ rendered: RenderedText) {
        host.rootView = Self.pane(rendered, keepingScroll: true)
        settle()
    }

    func scroll(to y: CGFloat) {
        guard let clipView else { return }
        clipView.scroll(to: NSPoint(x: clipView.bounds.minX, y: y))
        clipView.enclosingScrollView?.reflectScrolledClipView(clipView)
        settle()
    }

    /// Scrolls as far down as the scroller goes.
    func scrollToEnd() {
        guard let textView, let clipView else { return }
        scroll(to: textView.frame.height - clipView.bounds.height)
    }

    /// The rows TextKit has laid out in what shows, each with its top in the text view, read without laying anything
    /// out.
    func shownRows() -> [Int: CGFloat] {
        guard let textView, let layoutManager = textView.textLayoutManager,
            let content = layoutManager.textContentManager,
            let rendered = Self.first(DiffGutterView.self, in: host)?.rendered
        else { return [:] }
        let visible = textView.visibleRect
        let origin = textView.textContainerOrigin.y
        let start = layoutManager.documentRange.location
        var rows: [Int: CGFloat] = [:]
        layoutManager.enumerateTextLayoutFragments(from: start) { fragment in
            let frame = fragment.layoutFragmentFrame.offsetBy(dx: 0, dy: origin)
            guard fragment.state == .layoutAvailable, frame.maxY > visible.minY, frame.minY < visible.maxY else {
                return true
            }
            let offset = content.offset(from: start, to: fragment.rangeInElement.location)
            rows[rendered.rowIndex(containing: offset)] = frame.minY
            return true
        }
        return rows
    }

    /// Lays out and displays what needs it, and lets the run loop turn once, as it does between two events.
    private func settle() {
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0, true)
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
    }

    private static func first<View: NSView>(_ type: View.Type, in view: NSView) -> View? {
        if let match = view as? View { return match }
        return view.subviews.lazy.compactMap { first(type, in: $0) }.first
    }
}

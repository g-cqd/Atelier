import AppKit
import DiffCore
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
}

import AppKit
import DiffCore
import Foundation
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// A new render replaces a scrolling pane's whole text: the storage is emptied first, in the same editing transaction,
/// which spares TextKit a replace that is quadratic in a large text.
@MainActor
@Suite(.mainActorLane)
struct PaneStorageReplacementTests {
    @Test
    func `a new render into a pane holding a large text leaves exactly the new text`() throws {
        let before = Self.rendered(rows: 5_000, token: "before")
        let after = Self.rendered(rows: 5_000, token: "after")
        let scrollView = NSTextView.scrollableTextView()
        let textView = try #require(scrollView.documentView as? NSTextView)
        let sut = DiffTextViewCoordinator()
        sut.textView = textView
        sut.wrapsLines = false

        sut.apply(before)
        sut.apply(after)

        #expect(try #require(textView.textContentStorage?.textStorage).isEqual(to: after.attributed))
    }

    /// `rows` rows of `let <token> = 42`, coloured by row, as a pane shows a rendered text.
    static func rendered(rows: Int, token: String) -> RenderedText {
        let line = "let \(token) = 42"
        let length = line.utf16.count
        let source = Array(repeating: line, count: rows).joined(separator: "\n")
        let palette = DiffPalette.system
        let attributed = NSMutableAttributedString(string: source, attributes: [.font: palette.font])
        for row in 0 ..< rows {
            attributed.addAttribute(
                .foregroundColor, value: row.isMultiple(of: 2) ? NSColor.systemBlue : NSColor.systemOrange,
                range: NSRange(location: row * (length + 1), length: length))
        }
        return RenderedText(
            side: .unified, palette: palette, attributed: NSAttributedString(attributedString: attributed),
            rows: (0 ..< rows).map { RowMeta(kind: .context, oldNumber: $0 + 1, newNumber: $0 + 1) }, gaps: [],
            lineStarts: (0 ..< rows).map { $0 * (length + 1) }, longestLine: length)
    }
}

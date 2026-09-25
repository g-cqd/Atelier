import AppKit
import DiffCore
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// A text whose last rows are empty, such as an added file's side of fillers or a file ending in blank lines, lays
/// its last row out like any other row: as tall as the others, in its own colour, in cards and in the file pane.
@MainActor
@Suite(.mainActorLane)
struct EmptyLastRowTests {
    private static let added = "let first = 1\nlet second = 2\nlet third = 3\n"

    /// An added file's old side, all fillers; a file whose last two lines are blank on both sides.
    private static var sides: [RenderedText] {
        [
            DiffRenderer.render(oldText: "", newText: added, language: .plain, lineHeightMultiple: 1.2).old,
            DiffRenderer.render(oldText: "a\n\n\n", newText: "b\n\n\n", language: .plain, lineHeightMultiple: 1.2).new
        ]
        .compactMap { $0 }
    }

    private static func fragments(of layoutManager: NSTextLayoutManager) -> [DiffLayoutFragment] {
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        var fragments: [DiffLayoutFragment] = []
        layoutManager.enumerateTextLayoutFragments(from: nil, options: [.ensuresLayout]) {
            if let fragment = $0 as? DiffLayoutFragment { fragments.append(fragment) }
            return true
        }
        return fragments
    }

    @Test
    func `every row of a text ending in empty rows is as tall as the others and the unwrapped height is exact`() throws
    {
        for side in Self.sides {
            #expect(side.attributed.string.hasSuffix("\n") || side.attributed.length == 0)
            let laidOut = StaticTextLayout(rendered: side)
            laidOut.layOut(mode: .column(100_000), viewportWidth: 300)
            let analytic = StaticTextLayout(rendered: side)
            analytic.layOut(mode: .none, viewportWidth: 300)
            let heights = Self.fragments(of: laidOut.layoutManager).map(\.layoutFragmentFrame.height)
            #expect(heights == Array(repeating: side.lineHeight, count: side.rows.count))
            #expect(analytic.height == laidOut.height)
        }
    }

    @Test
    func `an empty last row is coloured as its own row, not as the row before it`() throws {
        // The old side is a context row, then a filler for the added line.
        let side = try #require(
            DiffRenderer.render(oldText: "x\n", newText: "x\ny\n", language: .plain, lineHeightMultiple: 1.2).old)
        #expect(side.rows.map(\.kind) == [.context, .filler])
        let layout = StaticTextLayout(rendered: side)
        layout.layOut(mode: .viewport, viewportWidth: 300)
        let fragments = Self.fragments(of: layout.layoutManager)
        #expect(fragments.count == 2)
        #expect(fragments.last?.backgroundColor == side.palette.rowBackground(for: .filler, side: .old))
    }

    @Test
    func `the file pane lays an empty last row out like the cards do`() throws {
        let side = try #require(Self.sides.last)
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)
        let sut = DiffTextViewCoordinator()
        sut.textView = textView
        textView.textLayoutManager?.delegate = sut.fragmentProvider
        sut.apply(side)
        #expect(textView.string == side.attributed.string + " ")
        let heights = try Self.fragments(of: #require(textView.textLayoutManager)).map(\.layoutFragmentFrame.height)
        #expect(heights.count == side.rows.count)
    }

    @Test
    func `a text whose last row has content is stored as rendered`() throws {
        let side = try #require(
            DiffRenderer.render(oldText: "a\n", newText: Self.added, language: .plain, lineHeightMultiple: 1.2).new)
        let layout = StaticTextLayout(rendered: side)
        #expect(layout.contentStorage.textStorage?.string == side.attributed.string)
    }
}

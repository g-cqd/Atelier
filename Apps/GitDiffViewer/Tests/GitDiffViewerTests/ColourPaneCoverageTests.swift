import AppKit
import AtelierSyntaxModel
import DiffCore
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// Syntax colour on every row a pane shows (PERF-09 stage 1), in every layout and at every moment that lays rows out
/// again: first paint, a scroll far down, a resize, and the file rendered again, as a fold or a gap reveal renders it.
/// Each row shown starts with `let`, which the lexer colours a keyword: every one must carry the keyword's colour as
/// a rendering attribute, since that is how a pane draws colour. A changed row keeps its diff background meanwhile.
@MainActor
@Suite(.mainActorLane)
struct ColourPaneCoverageTests {
    private static let count = 240
    private static let old = (1 ... count).map { "let value\($0) = \($0)" }.joined(separator: "\n") + "\n"
    private static let new = old.replacingOccurrences(of: "let value30 = 30\n", with: "let value30 = 31\n")

    private static func text(layout: RenderLayout = .full) -> PaneText {
        let prepared = PreparedDiff(
            FileDiffInput(title: "a.swift", oldText: old, newText: new, language: .swift), granularity: .word)
        let rendered = DiffRenderer.render(
            prepared: [prepared], options: DiffRenderer.Options(), layout: layout, withHeaders: false)
        return PaneText(rendered: rendered, asksForChange: true)
    }

    /// The lexer's colour of both sides, as the pipeline lands it.
    private static func decorations() async -> DiffDecorations {
        DecorationFixtures.colors(
            old: await DecorationFixtures.lexed(old, language: .swift),
            new: await DecorationFixtures.lexed(new, language: .swift))
    }

    /// Expects every numbered row laid out in each pane's viewport to start in the keyword's colour, and a changed
    /// row's fragment to keep its diff background.
    private static func expectColoured(_ sut: HostedPanes, _ moment: String) throws {
        for pane in try sut.panes() {
            let layoutManager = try #require(pane.textView.textLayoutManager)
            let content = try #require(layoutManager.textContentManager)
            let start = layoutManager.documentRange.location
            var coloured: [Range<Int>] = []
            let keyword = pane.rendered.palette.color(for: .keyword)
            layoutManager.enumerateRenderingAttributes(from: start, reverse: false) { _, attributes, range in
                if (attributes[.foregroundColor] as? NSColor) == keyword {
                    let lower = content.offset(from: start, to: range.location)
                    coloured.append(lower ..< lower + content.offset(from: range.location, to: range.endLocation))
                }
                return true
            }
            let viewport = try #require(layoutManager.textViewportLayoutController.viewportRange)
            var checked = 0
            layoutManager.enumerateTextLayoutFragments(from: viewport.location) { fragment in
                guard fragment.rangeInElement.location.compare(viewport.endLocation) == .orderedAscending else {
                    return false
                }
                let row = pane.rendered.rowIndex(
                    containing: content.offset(from: start, to: fragment.rangeInElement.location))
                let meta = pane.rendered.rows[row]
                guard meta.oldNumber != nil || meta.newNumber != nil else { return true }
                checked += 1
                let lineStart = pane.rendered.lineStarts[row]
                #expect(
                    coloured.contains { $0.contains(lineStart) },
                    "\(moment): row \(row) of the \(pane.rendered.side) pane is not coloured")
                if meta.kind == .added || meta.kind == .removed || meta.kind == .modified {
                    let expected = pane.rendered.palette.rowBackground(
                        for: meta.kind, side: pane.rendered.side, isMoved: false)
                    #expect((fragment as? DiffLayoutFragment)?.backgroundColor == expected, "\(moment): row \(row)")
                }
                return true
            }
            #expect(checked > 0, "\(moment): nothing laid out in the \(pane.rendered.side) pane")
        }
    }

    @Test(arguments: PaneLayout.allCases)
    func `every row shown keeps its syntax colour through scrolls, resizes and renders`(layout: PaneLayout)
        async throws
    {
        let decorations = await Self.decorations()
        let sut = HostedPanes(showing: Self.text(), layout: layout, wrapsLines: true, decorations: decorations)
        try await sut.alignSides()
        try Self.expectColoured(sut, "first paint")

        sut.scrollToEnd()
        try Self.expectColoured(sut, "scrolled to the end")

        sut.resize(to: NSSize(width: 460, height: HostedPanes.paneHeight + 80))
        try Self.expectColoured(sut, "resized")

        sut.show(Self.text(layout: .changes(context: 12, expansions: [:])))
        try await sut.alignSides()
        try Self.expectColoured(sut, "rendered again")
    }

    /// The rows laid out in `textView`'s viewport that show a line and do not start in the keyword's colour.
    private static func uncolouredRows(in textView: NSTextView, showing rendered: RenderedText) throws -> [Int] {
        let layoutManager = try #require(textView.textLayoutManager)
        let content = try #require(layoutManager.textContentManager)
        let start = layoutManager.documentRange.location
        let keyword = rendered.palette.color(for: .keyword)
        var coloured: [Range<Int>] = []
        layoutManager.enumerateRenderingAttributes(from: start, reverse: false) { _, attributes, range in
            if (attributes[.foregroundColor] as? NSColor) == keyword {
                let lower = content.offset(from: start, to: range.location)
                coloured.append(lower ..< lower + content.offset(from: range.location, to: range.endLocation))
            }
            return true
        }
        let viewport = try #require(layoutManager.textViewportLayoutController.viewportRange)
        var missing: [Int] = []
        layoutManager.enumerateTextLayoutFragments(from: viewport.location) { fragment in
            guard fragment.rangeInElement.location.compare(viewport.endLocation) == .orderedAscending else {
                return false
            }
            let row = rendered.rowIndex(containing: content.offset(from: start, to: fragment.rangeInElement.location))
            let meta = rendered.rows[row]
            if meta.oldNumber != nil || meta.newNumber != nil,
                !coloured.contains(where: { $0.contains(rendered.lineStarts[row]) })
            {
                missing.append(row)
            }
            return true
        }
        return missing
    }

    @Test
    func `rows keep their colour when an edit of the text's attributes lays them out again`() async throws {
        let rendered = try #require(Self.text().rendered.new)
        let pane = try HostedDecoratedPane(rendered: rendered, decorations: await Self.decorations())
        let textView = try pane.textView
        #expect(try Self.uncolouredRows(in: textView, showing: rendered).isEmpty)

        let storage = try #require(textView.textContentStorage)
        _ = RowSpacing.apply(Array(repeating: 6, count: rendered.rows.count), to: storage, rendered: rendered)
        pane.settle()

        #expect(try Self.uncolouredRows(in: textView, showing: rendered) == [])
    }
}

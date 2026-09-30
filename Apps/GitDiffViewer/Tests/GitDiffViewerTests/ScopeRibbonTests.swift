import AppKit
import AtelierSwiftSyntax
import DiffCore
import Metal
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// The gutter's scope ribbon (DIFF-03): it costs the gutter 2 pt, lands after the first paint without laying anything
/// out again, and outlines the scope of the row under the pointer, lighting its braces.
@MainActor
@Suite(
    .mainActorLane,
    .enabled(if: MTLCreateSystemDefaultDevice() != nil, "Core Animation's renderer draws into a Metal texture"))
struct ScopeRibbonTests {
    private static let text = ScopeLinesTests.text

    private static func rendered() throws -> RenderedText {
        try #require(DiffRenderer.render(oldText: text, newText: text, language: .swift).new)
    }

    /// The new side's scopes, landed at `version`.
    private static func scoped(version: Int = 1) throws -> DiffDecorations {
        DiffDecorations(new: .init(scopes: try ScopeLinesTests.scopes()), markVersion: version)
    }

    private static func gutter(of pane: HostedDecoratedPane) throws -> DiffGutterView {
        let content = try #require(pane.window.contentView)
        return try #require(firstSubview(DiffGutterView.self, in: content))
    }

    /// The ribbon's column down the whole gutter, in window coordinates.
    private static func ribbonBand(of gutter: DiffGutterView) -> NSRect {
        gutter.convert(
            NSRect(x: gutter.ribbonX, y: 0, width: DiffGutterView.ribbonWidth, height: gutter.bounds.height), to: nil)
    }

    @Test
    func `the gutter's width follows what it shows: the ribbon's own setting, and whether the change layer draws`()
        throws
    {
        // No compact changes and the standard colours: nothing for the change layer to draw, so it takes no width.
        let bare = DiffGutterView(clipView: nil)
        bare.style = .new
        bare.rendered = try Self.rendered()
        let bareWidth = bare.thickness

        bare.showsScopeRibbon = false
        // Turning the ribbon off reclaims its own width and the air before it.
        #expect(bare.thickness == bareWidth - (DiffGutterView.ribbonWidth + 2))

        let prepared = PreparedDiff(
            FileDiffInput(title: "", oldText: "let a = 1\n", newText: "let a = 2\n", language: .plain),
            granularity: .word)
        let compact = DiffRenderer.render(
            prepared: [prepared], options: DiffRenderer.Options(sides: [.unified], compactsInline: true),
            layout: .full, withHeaders: false)
        guard let compactRendered = compact.unified else {
            Issue.record("expected a unified render")
            return
        }
        let marked = DiffGutterView(clipView: nil)
        marked.style = .new
        marked.rendered = compactRendered

        // With a change to mark, the layer and its own negative space take their width back.
        #expect(marked.thickness == bareWidth + (ChangeMarkerLayout.hitWidth + 2))
    }

    @Test
    func `the ribbon lands after the first paint with no fragment laid out again`() throws {
        let pane = try HostedDecoratedPane(rendered: try Self.rendered(), decorations: nil)
        let gutter = try Self.gutter(of: pane)
        let layoutManager = try #require(try pane.textView.textLayoutManager)
        func fragments() -> [NSTextLayoutFragment] {
            var all: [NSTextLayoutFragment] = []
            _ = layoutManager.enumerateTextLayoutFragments(from: layoutManager.documentRange.location) {
                all.append($0)
                return true
            }
            return all
        }
        let before = fragments()
        let width = gutter.thickness
        let plain = try pane.pixels()

        pane.update(decorations: try Self.scoped())

        let sameFragments = fragments().elementsEqual(before, by: ===)
        #expect(sameFragments)
        #expect(gutter.thickness == width)
        let ribbon = try pane.pixels()
        #expect(ribbon.differing(from: plain, in: Self.ribbonBand(of: gutter)) > 0)
        #expect(ribbon.differing(from: plain, in: try pane.textBand(ofRow: 2)) == 0)
    }

    @Test
    func `hovering a row in the gutter or the text outlines its innermost scope and lights its braces`() throws {
        let rendered = try Self.rendered()
        let pane = try HostedDecoratedPane(rendered: rendered, decorations: try Self.scoped())
        let gutter = try Self.gutter(of: pane)
        let resting = try pane.pixels()

        gutter.hoverScope(atRow: 2)
        pane.settle()

        #expect(gutter.hoveredScope == HoveredScope(isOld: false, index: 1))
        #expect(try pane.pixels().differing(from: resting, in: Self.ribbonBand(of: gutter)) > 0)
        let open = rendered.lineStarts[1] + 13
        let close = rendered.lineStarts[3] + 4
        #expect(try pane.renderingColor(at: open) == .controlAccentColor)
        #expect(try pane.renderingColor(at: close) == .controlAccentColor)

        // Over the text, the pointer on the type's last row outlines the type, and the function's braces go out.
        let tracker = ScopeHoverTracker()
        tracker.attach(to: try pane.textView, gutter: gutter)
        defer { tracker.detach() }
        let row = try pane.textBand(ofRow: 5)
        tracker.pointerMoved(to: try pane.textView.convert(NSPoint(x: row.minX + 4, y: row.midY), from: nil))

        #expect(gutter.hoveredScope == HoveredScope(isOld: false, index: 0))
        #expect(try pane.renderingColor(at: open) == nil)
        #expect(try pane.renderingColor(at: rendered.lineStarts[0] + 9) == .controlAccentColor)

        gutter.hoverScope(atRow: nil)
        pane.settle()
        #expect(try pane.renderingColor(at: rendered.lineStarts[0] + 9) == nil)
        #expect(try pane.pixels().differing(from: resting, in: pane.bounds) == 0)
    }

    /// Hovering deep inside a tall scope, far from either brace, still finds it, in a file pane (book D43, "hover
    /// hits the wrong row"): the ribbon's own row lookup is a direct TextKit fragment lookup, not guessed from a
    /// window around some other row, so it is not the class of bug the change markers had.
    @Test
    func `hovering a row deep inside a tall scope finds it, far from either of its braces`() throws {
        let text = "struct S {\n" + (1 ... 20).map { "    let v\($0) = \($0)\n" }.joined() + "}\n"
        let rendered = try #require(DiffRenderer.render(oldText: text, newText: text, language: .swift).new)
        let facts = try #require(SwiftSyntaxFacts.extract(text))
        let scopes = ScopeLines(
            facts.scopes, text: text, lineRanges: DiffRenderer.lineRanges(of: text, lines: DiffModel.lines(of: text)))
        let pane = try HostedDecoratedPane(
            rendered: rendered, decorations: DiffDecorations(new: .init(scopes: scopes), markVersion: 1))
        let gutter = try Self.gutter(of: pane)

        gutter.hoverScope(atRow: 10)

        #expect(gutter.hoveredScope == HoveredScope(isOld: false, index: 0))
    }
}

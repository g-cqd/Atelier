import AppKit
import AtelierSwiftSyntax
import DiffCore
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// The gutter restyled after Xcode (book D43): the change markers back on the leading edge, 6 pt at rest and 8 pt on
/// hover; the ribbon's capsules, no stroke at rest and a light one on hover; a disclosed change's separator lines;
/// additions, modifications and removals drawn distinctly. Pixel tests compare bytes drawn in light and dark, since a
/// colour resolved wrong in one appearance often still looks fine in the other.
@MainActor
@Suite(.mainActorLane)
struct GutterXcodeStyleTests {
    nonisolated private static let appearances: [NSAppearance.Name] = [.aqua, .darkAqua]

    /// `gutter`'s pixels as it draws now, in `appearance`.
    private static func pixels(of gutter: DiffGutterView, appearance: NSAppearance.Name) -> Data? {
        gutter.appearance = NSAppearance(named: appearance)
        guard let bitmap = gutter.bitmapImageRepForCachingDisplay(in: gutter.bounds) else { return nil }
        gutter.cacheDisplay(in: gutter.bounds, to: bitmap)
        return bitmap.tiffRepresentation
    }

    /// A gutter over one added line, its bar the only marker.
    private static func markerGutter() throws -> (gutter: DiffGutterView, layout: StaticTextLayout, bar: CGRect) {
        let old = "let a = 1\nlet b = 2\nlet c = 3\n"
        let new = "let a = 1\nlet added = true\nlet b = 2\nlet c = 3\n"
        let prepared = PreparedDiff(
            FileDiffInput(title: "", oldText: old, newText: new, language: .plain), granularity: .word)
        let diff = DiffRenderer.render(
            prepared: [prepared], options: DiffRenderer.Options(sides: [.unified], compactsInline: true),
            layout: .full, withHeaders: false)
        let rendered = try #require(diff.unified)
        let layout = StaticTextLayout(rendered: rendered)
        layout.layOut(mode: .none, viewportWidth: 400)
        let gutter = DiffGutterView(clipView: nil)
        gutter.style = .new
        gutter.source = layout
        gutter.rendered = rendered
        gutter.frame = NSRect(x: 0, y: 0, width: gutter.thickness, height: layout.height)
        var found: CGRect?
        gutter.forEachChangeMarker(in: gutter.bounds) { _, shape in found = shape.rect }
        return (gutter, layout, try #require(found))
    }

    /// `gutter`'s colour at `point`, at its current backing scale.
    private static func color(of gutter: DiffGutterView, at point: NSPoint) throws -> NSColor {
        let bitmap = try #require(gutter.bitmapImageRepForCachingDisplay(in: gutter.bounds))
        gutter.cacheDisplay(in: gutter.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / gutter.bounds.width
        return try #require(bitmap.colorAt(x: Int(point.x * scale), y: Int(point.y * scale)))
    }

    @Test(arguments: appearances)
    func `a marker is 6 pt wide at rest and 8 pt under the pointer`(appearance: NSAppearance.Name) throws {
        let (gutter, layout, bar) = try Self.markerGutter()
        withExtendedLifetime(layout) {}
        gutter.appearance = NSAppearance(named: appearance)
        // Just inside the change layer's own edge: outside the 6 pt rest bar, centred with a margin either side, but
        // inside the 8 pt bar the pointer widens it to (book D43).
        let edge = NSPoint(x: gutter.changeLayerX + 0.4, y: bar.midY)
        let restEdge = try Self.color(of: gutter, at: edge)
        let resting = Self.pixels(of: gutter, appearance: appearance)

        gutter.setHoveredChange(try #require(gutter.changeMarker(at: NSPoint(x: bar.midX, y: bar.midY))?.key))
        let hoveredEdge = try Self.color(of: gutter, at: edge)
        let hovered = Self.pixels(of: gutter, appearance: appearance)

        #expect(resting != hovered)
        // At rest the edge lies outside the narrower bar, in the gutter's own background; under the pointer the bar
        // widens to fill the layer and reaches it.
        #expect(restEdge != hoveredEdge)
    }

    /// A gutter over a tall function, its ribbon the only capsule.
    private static func ribbonGutter() throws -> (pane: HostedDecoratedPane, gutter: DiffGutterView) {
        let text = "struct S {\n" + (1 ... 6).map { "    let v\($0) = \($0)\n" }.joined() + "}\n"
        let rendered = try #require(DiffRenderer.render(oldText: text, newText: text, language: .swift).new)
        let facts = try #require(SwiftSyntaxFacts.extract(text))
        let scopes = ScopeLines(
            facts.scopes, text: text, lineRanges: DiffRenderer.lineRanges(of: text, lines: DiffModel.lines(of: text)))
        let pane = try HostedDecoratedPane(
            rendered: rendered, decorations: DiffDecorations(new: .init(scopes: scopes), markVersion: 1))
        let content = try #require(pane.window.contentView)
        let gutter = try #require(firstSubview(DiffGutterView.self, in: content))
        return (pane, gutter)
    }

    @Test(arguments: appearances)
    func `the ribbon's capsules have no stroke at rest, and a light one on hover`(appearance: NSAppearance.Name)
        throws
    {
        let (pane, gutter) = try Self.ribbonGutter()
        pane.window.appearance = NSAppearance(named: appearance)
        gutter.appearance = NSAppearance(named: appearance)
        pane.settle()
        let resting = try pane.pixels()

        gutter.hoverScope(atRow: 2)
        pane.settle()
        let hovered = try pane.pixels()

        let band = gutter.convert(
            NSRect(x: gutter.ribbonX, y: 0, width: DiffGutterView.ribbonWidth, height: gutter.bounds.height), to: nil)
        #expect(hovered.differing(from: resting, in: band) > 0)
    }

    /// A modified change over two lines removed and two added, its key so it can be disclosed.
    private static func modifiedGutter(disclosed: Bool) throws -> (
        gutter: DiffGutterView, layout: StaticTextLayout, bar: CGRect
    ) {
        let old = "let a = 1\nlet old1 = 1\nlet old2 = 2\nlet z = 9\n"
        let new = "let a = 1\nlet new1 = 1\nlet new2 = 2\nlet z = 9\n"
        let prepared = PreparedDiff(
            FileDiffInput(title: "", oldText: old, newText: new, language: .plain), granularity: .word)
        let key = ChangeKey(fileIndex: 0, changeIndex: 0)
        let diff = DiffRenderer.render(
            prepared: [prepared],
            options: DiffRenderer.Options(
                sides: [.unified], compactsInline: true, disclosedChanges: disclosed ? [key] : []),
            layout: .full, withHeaders: false)
        let rendered = try #require(diff.unified)
        let layout = StaticTextLayout(rendered: rendered)
        layout.layOut(mode: .none, viewportWidth: 400)
        let gutter = DiffGutterView(clipView: nil)
        gutter.style = .new
        gutter.source = layout
        gutter.rendered = rendered
        gutter.frame = NSRect(x: 0, y: 0, width: gutter.thickness, height: layout.height)
        var found: CGRect?
        gutter.forEachChangeMarker(in: gutter.bounds) { change, shape in
            if change.kind == .modified { found = shape.rect }
        }
        return (gutter, layout, try #require(found))
    }

    @Test(arguments: appearances)
    func `a disclosed change's separators cut its outer edges and the seam between its old and new rows`(
        appearance: NSAppearance.Name
    ) throws {
        let (gutter, layout, bar) = try Self.modifiedGutter(disclosed: true)
        withExtendedLifetime(layout) {}
        gutter.appearance = NSAppearance(named: appearance)
        guard let bitmap = gutter.bitmapImageRepForCachingDisplay(in: gutter.bounds) else {
            Issue.record("no bitmap")
            return
        }
        gutter.cacheDisplay(in: gutter.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / gutter.bounds.width
        func color(_ point: NSPoint) -> NSColor? {
            bitmap.colorAt(x: Int(point.x * scale), y: Int(point.y * scale))
        }
        let seamY = bar.minY + CGFloat(2) * layout.rendered.lineHeight
        let seam = color(NSPoint(x: bar.midX, y: seamY))
        let insideOld = color(NSPoint(x: bar.midX, y: seamY - layout.rendered.lineHeight / 2))
        let insideNew = color(NSPoint(x: bar.midX, y: seamY + layout.rendered.lineHeight / 2))

        // The seam and the outer edge both cut through the gutter's own background, distinct from the coloured fill
        // either side of them.
        #expect(seam != insideOld)
        #expect(seam != insideNew)
        let topEdge = color(NSPoint(x: bar.midX, y: bar.minY + 0.5))
        let justBelowEdge = color(NSPoint(x: bar.midX, y: bar.minY + 2))
        #expect(topEdge != justBelowEdge)
    }

    @Test
    func `an addition, a modification and a removal draw with distinct colours`() {
        let palette = DiffPalette.system

        let added = palette.changeMarker(for: .added)
        let removed = palette.changeMarker(for: .removed)
        let modified = palette.changeMarker(for: .modified)

        #expect(added != removed)
        #expect(added != modified)
        #expect(removed != modified)
    }
}

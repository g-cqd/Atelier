import AppKit
import DiffCore
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// The minimap's bars follow the appearance and the backing scale they are drawn in, not the size alone
/// (text-renderer.md §1.3, finding 3; §5, M0 item 10).
@MainActor
@Suite(.mainActorLane)
struct MinimapBarsTests {
    private static func minimap() -> MinimapView {
        let text = (0 ..< 40).map { "let value\($0) = \($0)" }.joined(separator: "\n") + "\n"
        let changed = text.replacingOccurrences(of: "value7 =", with: "renamed7 =")
        let view = MinimapView(frame: NSRect(x: 0, y: 0, width: MinimapView.width, height: 200))
        view.rendered = DiffRenderer.render(oldText: text, newText: changed, language: .plain).new
        return view
    }

    /// Draws `view` offscreen, as a display pass would, and returns the bitmap.
    @discardableResult
    private static func draw(_ view: MinimapView) throws -> NSBitmapImageRep {
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap
    }

    @Test
    func `the bars are rasterized once while nothing changes`() throws {
        let view = Self.minimap()
        view.appearance = NSAppearance(named: .aqua)
        try Self.draw(view)
        try Self.draw(view)
        #expect(view.rasterizations == 1)
    }

    @Test
    func `a switch between light and dark rasterizes the bars again`() throws {
        let view = Self.minimap()
        view.appearance = NSAppearance(named: .aqua)
        try Self.draw(view)
        view.appearance = NSAppearance(named: .darkAqua)
        try Self.draw(view)
        #expect(view.rasterizations == 2)
        view.appearance = NSAppearance(named: .aqua)
        try Self.draw(view)
        #expect(view.rasterizations == 3)
    }

    @Test
    func `a new text rasterizes the bars again`() throws {
        let view = Self.minimap()
        view.appearance = NSAppearance(named: .aqua)
        try Self.draw(view)
        view.rendered = Self.minimap().rendered
        try Self.draw(view)
        #expect(view.rasterizations == 2)
    }
}

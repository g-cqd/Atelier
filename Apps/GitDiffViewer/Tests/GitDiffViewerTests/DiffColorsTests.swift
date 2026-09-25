import AppKit
import DiffCore
import Testing

@testable import DiffComparison
@testable import DiffRendering
@testable import DiffTextKit

/// The diff colours (book D18): the app's red and green by default, or Xcode's gray and blue with a change bar.
struct DiffColorsTests {
    private let standard = DiffPalette.system
    private let xcode = DiffPalette.system.with(diffColors: .xcode)

    @Test
    func `the default colours keep removed lines red and added ones green, with no change bar`() {
        #expect(standard.diffColors == .standard)
        #expect(standard.rowBackground(for: .removed, side: .unified) == NSColor.systemRed.withAlphaComponent(0.16))
        #expect(standard.rowBackground(for: .added, side: .unified) == NSColor.systemGreen.withAlphaComponent(0.16))
        #expect(standard.changeBar == nil)
    }

    @Test
    func `Xcode's colours show removed lines gray, added ones blue, and tan and blue tokens`() {
        #expect(xcode.rowBackground(for: .removed, side: .unified) == standard.textColor.withAlphaComponent(0.07))
        #expect(xcode.rowBackground(for: .modified, side: .old) == standard.textColor.withAlphaComponent(0.07))
        #expect(xcode.rowBackground(for: .added, side: .unified) == NSColor.systemBlue.withAlphaComponent(0.12))
        #expect(xcode.rowBackground(for: .modified, side: .new) == NSColor.systemBlue.withAlphaComponent(0.12))
        #expect(xcode.emphasis(for: .removed, side: .unified) == NSColor.systemOrange.withAlphaComponent(0.28))
        #expect(xcode.emphasis(for: .added, side: .unified) == NSColor.systemBlue.withAlphaComponent(0.3))
        #expect(xcode.changeBar == .systemBlue)
    }

    @Test
    func `switching the colours keeps the font and renders anew`() {
        #expect(xcode.font == standard.font)
        #expect(xcode.defaultLineHeight == standard.defaultLineHeight)
        #expect(xcode != standard)
        #expect(xcode.with(diffColors: .standard) == standard)
    }
}

/// The diff colours through the settings and the window model, and Xcode's change bar in the gutter.
@MainActor
@Suite(.mainActorLane)
struct DiffColorsSettingTests {
    private let harness = ModelTestHarness()

    @Test
    func `the diff colours are the app's own until Xcode's are chosen, and the palette follows`() {
        let sut = harness.makeSUT()
        #expect(sut.settings.diffColors == .standard)
        #expect(sut.palette.diffColors == .standard)

        sut.settings.diffColors = .xcode

        #expect(sut.palette.diffColors == .xcode)
    }

    @Test
    func `restoring the appearance defaults brings the app's own colours back`() {
        let sut = harness.makeSUT()
        sut.settings.diffColors = .xcode

        sut.settings.restoreDefaults(.appearance)

        #expect(sut.settings.diffColors == .standard)
    }

    /// A gutter over ten lines with line 5 changed, or a line added after it, in `palette`, drawn whole; the pixel at
    /// the leading padding of row `row`'s middle.
    private func leadingPixel(
        ofRow row: Int, palette: DiffPalette, adds: Bool = false, compact: Bool = false
    ) throws -> NSColor? {
        let old = (1 ... 10).map { "let value\($0) = \($0)" }
        var new = old
        if adds { new.insert("let added = true", at: 5) } else { new[4] = "let value5 = five" }
        let prepared = PreparedDiff(
            FileDiffInput(
                title: "", oldText: old.joined(separator: "\n") + "\n", newText: new.joined(separator: "\n") + "\n",
                language: .plain), granularity: .word)
        let options = DiffRenderer.Options(palette: palette, sides: [.unified], compactsInline: compact)
        let rendered = try #require(
            DiffRenderer.render(prepared: [prepared], options: options, layout: .full, withHeaders: false).unified)
        let layout = StaticTextLayout(rendered: rendered)
        layout.layOut(mode: .none, viewportWidth: 600)
        let gutter = DiffGutterView(clipView: nil)
        gutter.source = layout
        gutter.rendered = rendered
        gutter.frame = NSRect(x: 0, y: 0, width: gutter.thickness, height: layout.height)
        let bitmap = try #require(gutter.bitmapImageRepForCachingDisplay(in: gutter.bounds))
        gutter.cacheDisplay(in: gutter.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / gutter.bounds.width
        let y = layout.inset + (CGFloat(row) + 0.5) * rendered.lineHeight
        return bitmap.colorAt(x: Int(3.5 * scale), y: Int(y * scale))
    }

    @Test
    func `Xcode's colours draw a change bar beside a changed row, and none beside the others`() throws {
        let xcode = DiffPalette.system.with(diffColors: .xcode)
        // Inline, line 5 changed takes rows 4 (removed) and 5 (added).
        let changed = try leadingPixel(ofRow: 4, palette: xcode)
        let context = try leadingPixel(ofRow: 1, palette: xcode)

        #expect(changed != context)
        #expect(try leadingPixel(ofRow: 4, palette: .system) == context)
    }

    @Test
    func `the compact inline view keeps its markers in place of the change bar`() throws {
        let xcode = DiffPalette.system.with(diffColors: .xcode)
        let barred = try leadingPixel(ofRow: 5, palette: xcode, adds: true)

        // The added line is row 5 either way; compact, its marker is the addition's green, not the bar's blue.
        #expect(try leadingPixel(ofRow: 5, palette: xcode, adds: true, compact: true) != barred)
    }
}

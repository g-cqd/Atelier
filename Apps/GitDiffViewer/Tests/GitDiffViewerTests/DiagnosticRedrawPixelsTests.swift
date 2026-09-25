import AppKit
import AtelierDiagnostics
import DiffCore
import DiffRendering
import Foundation
import Metal
import QuartzCore
import SwiftUI
import Testing

@testable import DiffTextKit

/// What a scrolling pane shows once its diagnostics change, read from the contents its layer tree holds.
///
/// TextKit 2 draws each laid-out fragment into a layer-backed view of its own and keeps that drawing. The pixels come
/// from Core Animation's renderer, which composites what the layers hold, as the window server does:
/// `CALayer.render(in:)` makes AppKit draw every view again, and `cacheDisplay(in:to:)` redraws everything too, so
/// both show squiggles the screen never gets.
@MainActor
@Suite(.enabled(if: MTLCreateSystemDefaultDevice() != nil, "Core Animation's renderer draws into a Metal texture"))
struct DiagnosticRedrawPixelsTests {
    private static let rowCount = 12
    /// The row that carries the diagnostics; an odd row, so that its neighbours on both sides have none.
    private static let row = 5

    private static func diff() -> RenderedDiff {
        let text = (0 ..< rowCount).map { "let value\($0) = compute(\($0))" }.joined(separator: "\n") + "\n"
        return DiffRenderer.render(oldText: text, newText: text, language: .plain)
    }

    private static func rendered() throws -> RenderedText {
        try #require(diff().new)
    }

    private static func overlay(_ severity: Finding.Severity) -> DiagnosticOverlay {
        DiagnosticOverlay(rows: [row: diagnostics(severity)])
    }

    private static func diagnostics(_ severity: Finding.Severity) -> DiagnosticOverlay.RowDiagnostics {
        DiagnosticOverlay.RowDiagnostics(severity: severity, count: 1, findings: [], squiggles: [])
    }

    @Test(arguments: [false, true])
    func `a diagnostics bump redraws the squiggle of the row it changed`(wrapsLines: Bool) throws {
        let rendered = try Self.rendered()
        let overlay = Self.overlay(.error)
        let pane = try HostedPane(rendered: rendered, wrapsLines: wrapsLines, overlay: overlay)
        let before = try pane.pixels()

        overlay.replace([Self.row: Self.diagnostics(.warning)])
        pane.update(overlay: overlay, version: 1)

        let after = try pane.pixels()
        let fresh = try HostedPane(rendered: rendered, wrapsLines: wrapsLines, overlay: Self.overlay(.warning)).pixels()
        #expect(after.differing(from: before, in: try pane.textBand(ofRow: Self.row)) > 0)
        #expect(after.differing(from: fresh, in: pane.bounds) == 0)
    }

    @Test(arguments: [false, true])
    func `a diagnostics bump leaves the text of every other row as it was`(wrapsLines: Bool) throws {
        let overlay = Self.overlay(.error)
        let pane = try HostedPane(rendered: Self.rendered(), wrapsLines: wrapsLines, overlay: overlay)
        let before = try pane.pixels()

        overlay.replace([Self.row: Self.diagnostics(.warning)])
        pane.update(overlay: overlay, version: 1)

        let after = try pane.pixels()
        for row in 0 ..< Self.rowCount where row != Self.row {
            #expect(after.differing(from: before, in: try pane.textBand(ofRow: row)) == 0, "row \(row)")
        }
    }

    /// The control that makes the other tests mean something: the pixels come from what the layers hold, not from a
    /// fresh drawing, so a change nothing redraws stays off the screen.
    @Test
    func `a change the pane is not told of stays off the screen`() throws {
        let overlay = Self.overlay(.error)
        let pane = try HostedPane(rendered: Self.rendered(), wrapsLines: false, overlay: overlay)
        let before = try pane.pixels()

        overlay.replace([Self.row: Self.diagnostics(.warning)])
        pane.settle()

        #expect(try pane.pixels().differing(from: before, in: pane.bounds) == 0)
    }

    @Test
    func `turning diagnostics on draws the squiggles of rows laid out without them`() throws {
        let rendered = try Self.rendered()
        let pane = try HostedPane(rendered: rendered, wrapsLines: false, overlay: nil)
        let before = try pane.pixels()

        pane.update(overlay: Self.overlay(.error), version: 1)

        let after = try pane.pixels()
        let fresh = try HostedPane(rendered: rendered, wrapsLines: false, overlay: Self.overlay(.error)).pixels()
        #expect(after.differing(from: before, in: try pane.textBand(ofRow: Self.row)) > 0)
        #expect(after.differing(from: fresh, in: pane.bounds) == 0)
    }

    @Test
    func `turning diagnostics off clears the squiggles`() throws {
        let rendered = try Self.rendered()
        let pane = try HostedPane(rendered: rendered, wrapsLines: false, overlay: Self.overlay(.error))

        pane.update(overlay: nil, version: 1)

        let fresh = try HostedPane(rendered: rendered, wrapsLines: false, overlay: nil).pixels()
        #expect(try pane.pixels().differing(from: fresh, in: pane.bounds) == 0)
    }

    /// TextKit keeps its fragment objects through a layout invalidation, but lays their lines out anew.
    @Test
    func `a diagnostics bump lays no fragment out again`() throws {
        let overlay = Self.overlay(.error)
        let pane = try HostedPane(rendered: Self.rendered(), wrapsLines: false, overlay: overlay)
        let layoutManager = try #require(pane.textView.textLayoutManager)
        var fragments: [NSTextLayoutFragment] = []
        _ = layoutManager.enumerateTextLayoutFragments(from: layoutManager.documentRange.location) { fragment in
            fragments.append(fragment)
            return true
        }
        let lines = fragments.map(\.textLineFragments)
        try #require(fragments.count >= Self.rowCount)

        overlay.replace([Self.row: Self.diagnostics(.warning)])
        pane.update(overlay: overlay, version: 1)

        #expect(zip(fragments, lines).allSatisfy { $0.textLineFragments.elementsEqual($1, by: ===) })
    }
    // MARK: Card panes

    /// A finding with a column, underlined across its range (book DIAG-03).
    private static func ranged(_ severity: Finding.Severity) -> DiagnosticOverlay {
        let squiggle = DiagnosticOverlay.SquiggleRange(start: 4, end: 9, severity: severity)
        return DiagnosticOverlay(
            rows: [row: .init(severity: severity, count: 1, findings: [], squiggles: [squiggle])])
    }

    @Test
    func `a card pane underlines a row's finding and marks its line number`() throws {
        let diff = Self.diff()
        let bare = try HostedCardPane(diff: diff, overlay: nil).pixels()

        let pane = try HostedCardPane(diff: diff, overlay: Self.ranged(.error))

        let drawn = try pane.pixels()
        #expect(drawn.differing(from: bare, in: try pane.textBand(ofRow: Self.row)) > 0)
        #expect(drawn.differing(from: bare, in: try pane.gutterBand(ofRow: Self.row)) > 0)
        for row in 0 ..< Self.rowCount where row != Self.row {
            #expect(drawn.differing(from: bare, in: try pane.textBand(ofRow: row)) == 0, "row \(row)")
        }
    }

    @Test
    func `a diagnostics bump in a card pane draws what a fresh card pane draws`() throws {
        let diff = Self.diff()
        let overlay = Self.ranged(.error)
        let pane = try HostedCardPane(diff: diff, overlay: overlay)
        let before = try pane.pixels()

        overlay.replace(Self.ranged(.warning).snapshot())
        pane.update(overlay: overlay, version: 1)

        let after = try pane.pixels()
        let fresh = try HostedCardPane(diff: diff, overlay: Self.ranged(.warning)).pixels()
        #expect(after.differing(from: before, in: try pane.textBand(ofRow: Self.row)) > 0)
        #expect(after.differing(from: fresh, in: pane.bounds) == 0)
    }
}

/// An ``EmbeddedDiffTextView`` hosted as a card's body hosts it, at the height it measures, in a borderless window
/// that is never ordered in.
@MainActor
private final class HostedCardPane {
    private static let width: CGFloat = 600
    let window: NSWindow
    private let host: NSHostingView<EmbeddedDiffTextView>
    private let layouts: CardLayouts
    private let rendered: RenderedText

    init(diff: RenderedDiff, overlay: DiagnosticOverlay?) throws {
        rendered = try #require(diff.new)
        layouts = CardLayouts(rendered: diff)
        host = NSHostingView(rootView: Self.pane(layouts, overlay: overlay, version: 0))
        let height = host.fittingSize.height
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: max(height, 1)), styleMask: [.borderless],
            backing: .buffered, defer: false)
        window.contentView = host
        settle()
        try #require(host.layer != nil)
    }

    private static func pane(_ layouts: CardLayouts, overlay: DiagnosticOverlay?, version: Int) -> EmbeddedDiffTextView
    {
        EmbeddedDiffTextView(
            layouts: layouts, side: .new, gutter: .new, width: width, wrapMode: .none, diagnosticOverlay: overlay,
            diagnosticsVersion: version)
    }

    var bounds: NSRect { host.bounds }

    /// Hands the pane its diagnostics as SwiftUI does, then lets the change reach the screen.
    func update(overlay: DiagnosticOverlay?, version: Int) {
        host.rootView = Self.pane(layouts, overlay: overlay, version: version)
        settle()
    }

    func settle() {
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0, true)
    }

    func textBand(ofRow row: Int) throws -> NSRect {
        let band = try rowBand(row)
        let gutter = try #require(HostedPane.first(DiffGutterView.self, in: host))
        let textStart = gutter.convert(gutter.bounds, to: nil).maxX
        return NSRect(x: textStart, y: band.minY, width: bounds.width - textStart, height: band.height)
    }

    func gutterBand(ofRow row: Int) throws -> NSRect {
        let band = try rowBand(row)
        let gutter = try #require(HostedPane.first(DiffGutterView.self, in: host))
        let frame = gutter.convert(gutter.bounds, to: nil)
        return NSRect(x: frame.minX, y: band.minY, width: frame.width - 1, height: band.height)
    }

    /// Where `row` lies in the window.
    private func rowBand(_ row: Int) throws -> NSRect {
        let textView = try #require(HostedPane.first(NSTextView.self, in: host))
        let layoutManager = try #require(textView.textLayoutManager)
        let contentManager = try #require(layoutManager.textContentManager)
        let location = try #require(
            contentManager.location(layoutManager.documentRange.location, offsetBy: rendered.lineStarts[row]))
        let fragment = try #require(layoutManager.textLayoutFragment(for: location))
        var frame = fragment.layoutFragmentFrame
        frame.origin.y += textView.textContainerOrigin.y
        return textView.convert(frame, to: nil)
    }

    func pixels() throws -> LayerPixels {
        try LayerPixels.composite(try #require(host.layer))
    }
}

/// A ``DiffTextView`` hosted as the app hosts it, in a borderless window that is never ordered in.
@MainActor
private final class HostedPane {
    let window: NSWindow
    private let host: NSHostingView<DiffTextView>
    private let rendered: RenderedText
    private let wrapsLines: Bool

    init(rendered: RenderedText, wrapsLines: Bool, overlay: DiagnosticOverlay?) throws {
        self.rendered = rendered
        self.wrapsLines = wrapsLines
        host = NSHostingView(rootView: Self.pane(rendered, wrapsLines: wrapsLines, overlay: overlay, version: 0))
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.borderless], backing: .buffered,
            defer: false)
        window.contentView = host
        settle()
        try #require(host.layer != nil)
    }

    private static func pane(
        _ rendered: RenderedText, wrapsLines: Bool, overlay: DiagnosticOverlay?, version: Int
    ) -> DiffTextView {
        DiffTextView(
            rendered: rendered, gutter: .new, wrapsLines: wrapsLines, diagnosticOverlay: overlay,
            diagnosticsVersion: version)
    }

    var bounds: NSRect { host.bounds }

    var textView: NSTextView {
        get throws { try #require(Self.first(NSTextView.self, in: host)) }
    }

    /// Hands the pane its diagnostics as SwiftUI does, then lets the change reach the screen.
    func update(overlay: DiagnosticOverlay?, version: Int) {
        host.rootView = Self.pane(rendered, wrapsLines: wrapsLines, overlay: overlay, version: version)
        settle()
    }

    /// Lays out, displays what needs it, and lets the run loop turn once, as it does between two events.
    func settle() {
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0, true)
    }

    /// Where `row`'s text lies in the window, right of the gutter, whose badge is taller than its row.
    func textBand(ofRow row: Int) throws -> NSRect {
        let textView = try textView
        let layoutManager = try #require(textView.textLayoutManager)
        let contentManager = try #require(layoutManager.textContentManager)
        let location = try #require(
            contentManager.location(layoutManager.documentRange.location, offsetBy: rendered.lineStarts[row]))
        let fragment = try #require(layoutManager.textLayoutFragment(for: location))
        var frame = fragment.layoutFragmentFrame
        frame.origin.y += textView.textContainerOrigin.y
        let rowInWindow = textView.convert(frame, to: nil)
        let gutter = try #require(Self.first(DiffGutterView.self, in: host))
        let textStart = gutter.convert(gutter.bounds, to: nil).maxX
        return NSRect(x: textStart, y: rowInWindow.minY, width: bounds.width - textStart, height: rowInWindow.height)
    }

    /// The window's pixels as its layers hold them: Core Animation composites the layer tree into a texture, and no
    /// view is asked to draw.
    func pixels() throws -> LayerPixels {
        try LayerPixels.composite(try #require(host.layer))
    }

    static func first<View: NSView>(_ type: View.Type, in view: NSView) -> View? {
        if let match = view as? View { return match }
        return view.subviews.lazy.compactMap { first(type, in: $0) }.first
    }
}

/// Core Animation's renderer, the texture it draws into and the queue it encodes on, one for each size of window.
///
/// Making a renderer loads Core Animation's Metal shaders, which took tens of milliseconds on the main actor for each
/// frame read, so the suite makes one per size and reuses it, as the window server composites every frame with one.
@MainActor
private final class Compositor {
    let renderer: CARenderer
    let texture: any MTLTexture
    let queue: any MTLCommandQueue

    private static var bySize: [SIMD2<Int>: Compositor] = [:]

    /// The compositor for a window of `width` by `height` points, made the first time one is asked for.
    static func shared(width: Int, height: Int) throws -> Compositor {
        let size = SIMD2(width, height)
        if let compositor = bySize[size] { return compositor }
        let compositor = try Compositor(width: width, height: height)
        bySize[size] = compositor
        return compositor
    }

    private init(width: Int, height: Int) throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        queue = try #require(device.makeCommandQueue())
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        texture = try #require(device.makeTexture(descriptor: descriptor))
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        renderer = CARenderer(
            mtlTexture: texture, options: [kCARendererColorSpace: colorSpace, kCARendererMetalCommandQueue: queue])
    }
}

extension LayerPixels {
    /// `root`'s pixels as its layers hold them: Core Animation composites the layer tree into a texture, and no view
    /// is asked to draw.
    @MainActor
    static func composite(_ root: CALayer) throws -> LayerPixels {
        let width = Int(root.bounds.width)
        let height = Int(root.bounds.height)
        let compositor = try Compositor.shared(width: width, height: height)
        let renderer = compositor.renderer
        let region = MTLRegionMake2D(0, 0, width, height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        // The texture starts each frame empty, so that nothing an earlier pane left in it shows through.
        compositor.texture.replace(region: region, mipmapLevel: 0, withBytes: bytes, bytesPerRow: width * 4)
        renderer.layer = root
        renderer.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        // The renderer draws what was committed.
        CATransaction.flush()
        renderer.beginFrame(atTime: CACurrentMediaTime(), timeStamp: nil)
        renderer.addUpdate(renderer.bounds)
        renderer.render()
        renderer.endFrame()
        // The renderer encodes on the compositor's queue, so a buffer committed after its work completes after it.
        let fence = try #require(compositor.queue.makeCommandBuffer())
        fence.commit()
        fence.waitUntilCompleted()
        renderer.layer = nil
        compositor.texture.getBytes(&bytes, bytesPerRow: width * 4, from: region, mipmapLevel: 0)
        return LayerPixels(width: width, height: height, bytes: bytes)
    }
}

/// BGRA pixels at one per point, the bottom row first, as window coordinates count.
private struct LayerPixels {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    /// How many pixels inside `rect`, in window coordinates, differ from `other`'s by more than rounding does.
    ///
    /// A row whose bytes match in both holds no such pixel, so only the rows that differ are read pixel by pixel. This
    /// is a main-actor suite: reading every pixel of the window, as most counts here do, held the main actor for
    /// seconds, and every main-actor test in the run waited behind it.
    func differing(from other: LayerPixels, in rect: NSRect) -> Int {
        let rows = Self.clamped(rect.minY, rect.maxY, to: height)
        let columns = Self.clamped(rect.minX, rect.maxX, to: width)
        let rowBytes = columns.count * 4
        return bytes.withUnsafeBytes { mine in
            other.bytes.withUnsafeBytes { theirs in
                guard rowBytes > 0, let mineStart = mine.baseAddress, let theirsStart = theirs.baseAddress else {
                    return 0
                }
                var count = 0
                for y in rows {
                    let start = (y * width + columns.lowerBound) * 4
                    guard memcmp(mineStart + start, theirsStart + start, rowBytes) != 0 else { continue }
                    for index in stride(from: start, to: start + rowBytes, by: 4)
                    where (0 ..< 3).contains(where: { abs(Int(mine[index + $0]) - Int(theirs[index + $0])) > 8 }) {
                        count += 1
                    }
                }
                return count
            }
        }
    }

    /// The whole pixels from `lower` to `upper` that lie within `0 ..< limit`; empty for a span outside it.
    private static func clamped(_ lower: CGFloat, _ upper: CGFloat, to limit: Int) -> Range<Int> {
        let start = min(max(Int(lower.rounded(.down)), 0), limit)
        return start ..< min(max(Int(upper.rounded(.up)), start), limit)
    }
}

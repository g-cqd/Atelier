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

    private static func rendered() throws -> RenderedText {
        let text = (0 ..< rowCount).map { "let value\($0) = compute(\($0))" }.joined(separator: "\n") + "\n"
        return try #require(DiffRenderer.render(oldText: text, newText: text, language: .plain).new)
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
        let root = try #require(host.layer)
        let width = Int(root.bounds.width)
        let height = Int(root.bounds.height)
        let device = try #require(MTLCreateSystemDefaultDevice())
        let queue = try #require(device.makeCommandQueue())
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        let texture = try #require(device.makeTexture(descriptor: descriptor))
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let renderer = CARenderer(
            mtlTexture: texture, options: [kCARendererColorSpace: colorSpace, kCARendererMetalCommandQueue: queue])
        renderer.layer = root
        renderer.bounds = CGRect(x: 0, y: 0, width: width, height: height)
        // The renderer draws what was committed.
        CATransaction.flush()
        renderer.beginFrame(atTime: CACurrentMediaTime(), timeStamp: nil)
        renderer.addUpdate(renderer.bounds)
        renderer.render()
        renderer.endFrame()
        // The renderer encodes on `queue`, so a buffer committed after its work completes after it.
        let fence = try #require(queue.makeCommandBuffer())
        fence.commit()
        fence.waitUntilCompleted()
        renderer.layer = nil
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&bytes, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return LayerPixels(width: width, height: height, bytes: bytes)
    }

    private static func first<View: NSView>(_ type: View.Type, in view: NSView) -> View? {
        if let match = view as? View { return match }
        return view.subviews.lazy.compactMap { first(type, in: $0) }.first
    }
}

/// BGRA pixels at one per point, the bottom row first, as window coordinates count.
private struct LayerPixels {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    /// How many pixels inside `rect`, in window coordinates, differ from `other`'s by more than rounding does.
    func differing(from other: LayerPixels, in rect: NSRect) -> Int {
        let rows = Self.clamped(rect.minY, rect.maxY, to: height)
        let columns = Self.clamped(rect.minX, rect.maxX, to: width)
        var count = 0
        for y in rows {
            for x in columns {
                let index = (y * width + x) * 4
                let channels = (0 ..< 3).map { abs(Int(bytes[index + $0]) - Int(other.bytes[index + $0])) }
                if channels.contains(where: { $0 > 8 }) { count += 1 }
            }
        }
        return count
    }

    /// The whole pixels from `lower` to `upper` that lie within `0 ..< limit`; empty for a span outside it.
    private static func clamped(_ lower: CGFloat, _ upper: CGFloat, to limit: Int) -> Range<Int> {
        let start = min(max(Int(lower.rounded(.down)), 0), limit)
        return start ..< min(max(Int(upper.rounded(.up)), start), limit)
    }
}

import AppKit
import Foundation
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// The panel's background (book HOVER-08): Liquid Glass by default, the popover material when the setting asks for
/// it, and either one clipped to the panel's rounded corners in a clear window, so no square corner shows.
@MainActor
@Suite(.mainActorLane)
struct HoverPanelMaterialTests {
    private static let document = HoverDocument(
        declaration: NSAttributedString(
            string: "struct CameraConfiguration",
            attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)]),
        summary: NSAttributedString(
            string: "A value type describing how a capture session should be configured.",
            attributes: [.font: NSFont.systemFont(ofSize: 12)]))

    private func preparedPanel(
        _ document: HoverDocument, material: HoverPanelMaterial = .liquidGlass,
        panel: HoverDocPanel = HoverDocPanel(ordersWindowIn: false)
    ) throws -> HoverDocPanel {
        panel.prepareOffscreenForTests(
            document: document, material: material, appearance: try #require(NSAppearance(named: .aqua)))
        return panel
    }

    /// The corner radius and mask the panel's background is clipped by, whichever material it is.
    private func clipping(of background: NSView) -> (radius: CGFloat?, maskInset: CGFloat?) {
        if let glass = background as? NSGlassEffectView { return (glass.cornerRadius, nil) }
        guard let effectView = background as? NSVisualEffectView else { return (nil, nil) }
        return (effectView.layer?.cornerRadius, effectView.maskImage?.capInsets.top)
    }

    @Test
    func `a panel is made of regular liquid glass by default`() throws {
        let panel = try preparedPanel(Self.document)

        let glass = try #require(panel.contentViewForTests as? NSGlassEffectView)
        #expect(glass.style == .regular)
        #expect(glass.tintColor == nil)
    }

    @Test
    func `a panel is made of the popover material when the setting asks for it`() throws {
        let panel = try preparedPanel(Self.document, material: .popover)

        let effectView = try #require(panel.contentViewForTests as? NSVisualEffectView)
        #expect(effectView.material == .popover)
        #expect(effectView.blendingMode == .behindWindow)
    }

    @Test(arguments: HoverPanelMaterial.allCases)
    func `the background is clipped to the panel's corners in a clear window`(material: HoverPanelMaterial) throws {
        let panel = try preparedPanel(Self.document, material: material)
        let background = try #require(panel.contentViewForTests)
        let window = try #require(panel.windowForTests)

        let (radius, maskInset) = clipping(of: background)

        #expect(radius == HoverPanelMetrics.panelCornerRadius)
        if material == .popover { #expect(maskInset == HoverPanelMetrics.panelCornerRadius) }
        #expect(!window.isOpaque)
        #expect(window.backgroundColor.alphaComponent == 0)
    }

    /// Drawn offscreen, the pixel in the corner, outside the rounded shape, is transparent, while the one in the middle
    /// of the same edge is not: the material stops at the curve, not at the square. Read as bytes: a transparent pixel
    /// is all zeros, premultiplied or not.
    @Test(arguments: HoverPanelMaterial.allCases)
    func `no square corner of the material shows past the rounded shape`(material: HoverPanelMaterial) throws {
        let panel = try preparedPanel(Self.document, material: material)
        let background = try #require(panel.contentViewForTests)
        background.layoutSubtreeIfNeeded()
        let bitmap = try #require(background.bitmapImageRepForCachingDisplay(in: background.bounds))
        background.cacheDisplay(in: background.bounds, to: bitmap)
        let bytes = try #require(bitmap.bitmapData)
        let bytesPerPixel = bitmap.bitsPerPixel / 8
        try #require(!bitmap.isPlanar && bitmap.bitsPerPixel % 8 == 0)
        func isTransparent(x: Int, y: Int) -> Bool {
            let pixel = bytes + y * bitmap.bytesPerRow + x * bytesPerPixel
            return (0 ..< bytesPerPixel).allSatisfy { pixel[$0] == 0 }
        }

        #expect(isTransparent(x: 0, y: 0))
        #expect(isTransparent(x: bitmap.pixelsWide - 1, y: bitmap.pixelsHigh - 1))
        #expect(!isTransparent(x: bitmap.pixelsWide / 2, y: 0))
    }

    /// A panel kept from one hover to the next takes the material of each document it shows, its content moving along.
    @Test
    func `a panel shown again follows a changed material, content and all`() throws {
        let panel = HoverDocPanel(ordersWindowIn: false)
        for material in [HoverPanelMaterial.liquidGlass, .popover, .liquidGlass] {
            _ = try preparedPanel(Self.document, material: material, panel: panel)
            let background = try #require(panel.contentViewForTests)
            background.layoutSubtreeIfNeeded()

            #expect((background is NSGlassEffectView) == (material == .liquidGlass))
            let texts = sequence(state: [background]) { pending -> NSView? in
                guard let view = pending.popLast() else { return nil }
                pending.append(contentsOf: view.subviews)
                return view
            }
            .compactMap { ($0 as? NSTextView)?.string }
            #expect(texts.contains("struct CameraConfiguration"), "\(material)")
        }
    }
}

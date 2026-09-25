import AppKit
import AtelierSyntaxModel
import Foundation
import Testing

@testable import DiffRendering
@testable import DiffTextKit

@MainActor
@Suite(.mainActorLane) struct HoverDocPanelRenderingTests {
    private static let markdown = """
        ```swift
        func greet(name: String) -> String
        ```

        Summarizes a greeting for the given name.

        Read [the guide](https://example.com/guide) before calling it.

        - Parameters:
          - name: The person to greet.
        - Returns: The greeting text.
        """

    /// On the popover material: drawn offscreen, Liquid Glass draws its own shape over the content it composites
    /// on screen, so no ink would show against it.
    private func preparedPanel(dark: Bool) throws -> HoverDocPanel {
        let name: NSAppearance.Name = dark ? .darkAqua : .aqua
        let appearance = try #require(NSAppearance(named: name))
        let document = HoverDocument.build(
            from: HoverContent(markdown: Self.markdown, source: .languageServer), palette: .system)
        let panel = HoverDocPanel(ordersWindowIn: false)
        panel.prepareOffscreenForTests(document: document, material: .popover, appearance: appearance)
        return panel
    }

    nonisolated private static let sectionLabels = ["PARAMETERS", "name"]

    /// The panel in one appearance, drawn whole and then without each part the tests below compare it without, with
    /// its body's layout read before any drawing. Drawing a 2x panel is most of this main-actor suite's time, so it is
    /// drawn once per appearance for the whole suite, each drawing serving several tests. Each part is cleared, drawn
    /// without, and restored in turn, the body last, and nothing reads the panel after that.
    private struct Drawings {
        let bodyHeight: CGFloat
        let bodyLayoutHeight: CGFloat
        let full: NSBitmapImageRep
        let withoutBody: NSBitmapImageRep
        let withoutLabel: [String: NSBitmapImageRep]
    }

    private static var drawings: [Bool: Drawings] = [:]

    private func drawings(dark: Bool) throws -> Drawings {
        if let drawn = Self.drawings[dark] { return drawn }
        let panel = try preparedPanel(dark: dark)
        let root = try #require(panel.contentViewForTests)
        let body = try #require(
            descendants(of: root, as: NSTextView.self).first { $0.string.contains("Summarizes a greeting") })
        let container = try #require(body.textContainer)
        let bodyLayoutHeight =
            body.textLayoutManager?.usageBoundsForTextContainer.height
            ?? body.layoutManager?.usedRect(for: container).height ?? 0
        let bodyHeight = body.bounds.height

        let full = try bitmap(of: root)
        var withoutLabel: [String: NSBitmapImageRep] = [:]
        for label in Self.sectionLabels {
            let field = try #require(descendants(of: root, as: NSTextField.self).first { $0.stringValue == label })
            let original = field.textColor
            field.textColor = .clear
            withoutLabel[label] = try bitmap(of: root)
            field.textColor = original
        }
        let original = body.attributedString()
        body.textStorage?.setAttributedString(NSAttributedString())
        let withoutBody = try bitmap(of: root)
        body.textStorage?.setAttributedString(original)

        let drawn = Drawings(
            bodyHeight: bodyHeight, bodyLayoutHeight: bodyLayoutHeight, full: full, withoutBody: withoutBody,
            withoutLabel: withoutLabel)
        Self.drawings[dark] = drawn
        return drawn
    }

    private func descendants<View: NSView>(of root: NSView, as type: View.Type) -> [View] {
        var found: [View] = []
        var pending = [root]
        while let view = pending.popLast() {
            if let match = view as? View { found.append(match) }
            pending.append(contentsOf: view.subviews)
        }
        return found
    }

    private func bitmap(of view: NSView) throws -> NSBitmapImageRep {
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap
    }

    /// A pixel's colour as the comparisons below read it: its device RGB components, and its luminance.
    private struct PixelColor {
        let deviceRGB: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat)?
        let luminance: CGFloat?
    }

    private func pixelColor(_ color: NSColor) -> PixelColor {
        let device = color.usingColorSpace(.deviceRGB)
        return PixelColor(
            deviceRGB: device.map { ($0.redComponent, $0.greenComponent, $0.blueComponent, $0.alphaComponent) },
            luminance: luminance(color))
    }

    private func colorDifference(_ lhs: PixelColor, _ rhs: PixelColor) -> CGFloat {
        guard let a = lhs.deviceRGB, let b = rhs.deviceRGB else { return 0 }
        return max(max(abs(a.red - b.red), abs(a.green - b.green)), max(abs(a.blue - b.blue), abs(a.alpha - b.alpha)))
    }

    /// Two bitmaps of one layout, read byte by byte: a pixel whose samples match in both is the same color, so the
    /// comparisons below make `NSColor`s only for the pixels that differ. Making two for every pixel held the main actor
    /// for seconds per test, and every main-actor test in the suite waited behind it.
    private struct SameLayoutBytes {
        private let first: NSBitmapImageRep
        private let second: NSBitmapImageRep
        private let firstBytes: UnsafeMutablePointer<UInt8>
        private let secondBytes: UnsafeMutablePointer<UInt8>
        private let bytesPerRow: Int
        private let bytesPerPixel: Int

        /// Nil unless both bitmaps store their pixels alike, meshed and in whole bytes, at most eight to a pixel.
        init?(_ first: NSBitmapImageRep, _ second: NSBitmapImageRep) {
            guard !first.isPlanar, !second.isPlanar, first.bitsPerPixel % 8 == 0, first.bitsPerPixel <= 64,
                first.bitsPerPixel == second.bitsPerPixel, first.bytesPerRow == second.bytesPerRow,
                first.bitmapFormat == second.bitmapFormat, first.colorSpace == second.colorSpace,
                first.pixelsWide == second.pixelsWide, first.pixelsHigh == second.pixelsHigh,
                let firstBytes = first.bitmapData, let secondBytes = second.bitmapData
            else { return nil }
            self.first = first
            self.second = second
            self.firstBytes = firstBytes
            self.secondBytes = secondBytes
            bytesPerRow = first.bytesPerRow
            bytesPerPixel = first.bitsPerPixel / 8
        }

        /// Whether row `y`, as `colorAt(x:y:)` reads it, holds the same samples in both, pixel for pixel. Most rows do,
        /// and a row compared whole costs one call where its pixels cost one each.
        func sameRow(_ y: Int) -> Bool {
            memcmp(firstBytes + y * bytesPerRow, secondBytes + y * bytesPerRow, first.pixelsWide * bytesPerPixel) == 0
        }

        /// Whether the pixel at `x`, `y`, in row `y` as `colorAt(x:y:)` reads it, holds the same samples in both.
        func samePixel(x: Int, y: Int) -> Bool {
            let offset = y * bytesPerRow + x * bytesPerPixel
            return memcmp(firstBytes + offset, secondBytes + offset, bytesPerPixel) == 0
        }

        /// The samples of the pixel at `x`, `y` in each bitmap, as one number apiece: `colorAt(x:y:)` makes a colour
        /// from those samples alone, and both bitmaps store them alike, so equal numbers are the same colour.
        func samples(x: Int, y: Int) -> (first: UInt64, second: UInt64) {
            let offset = y * bytesPerRow + x * bytesPerPixel
            var first: UInt64 = 0
            var second: UInt64 = 0
            withUnsafeMutableBytes(of: &first) {
                $0.copyMemory(from: UnsafeRawBufferPointer(start: firstBytes + offset, count: bytesPerPixel))
            }
            withUnsafeMutableBytes(of: &second) {
                $0.copyMemory(from: UnsafeRawBufferPointer(start: secondBytes + offset, count: bytesPerPixel))
            }
            return (first, second)
        }
    }

    /// How many pixels of `first` `counts` holds true for with the one at the same place in `second`. Only pixels
    /// whose bytes differ are read, and each distinct pixel value becomes a colour once: making colours for every
    /// differing pixel held the main actor for a large part of this suite's time.
    private func countPixels(
        _ first: NSBitmapImageRep, _ second: NSBitmapImageRep, where counts: (PixelColor, PixelColor) -> Bool
    ) -> Int {
        let bytes = SameLayoutBytes(first, second)
        var colors: [UInt64: PixelColor] = [:]
        func color(of bitmap: NSBitmapImageRep, x: Int, y: Int, samples: UInt64?) -> PixelColor? {
            if let samples, let made = colors[samples] { return made }
            guard let color = bitmap.colorAt(x: x, y: y) else { return nil }
            let made = pixelColor(color)
            if let samples { colors[samples] = made }
            return made
        }
        var count = 0
        for y in 0 ..< first.pixelsHigh where bytes?.sameRow(y) != true {
            for x in 0 ..< first.pixelsWide {
                if bytes?.samePixel(x: x, y: y) == true { continue }
                let samples = bytes?.samples(x: x, y: y)
                guard let one = color(of: first, x: x, y: y, samples: samples?.first),
                    let other = color(of: second, x: x, y: y, samples: samples?.second)
                else { continue }
                if counts(one, other) { count += 1 }
            }
        }
        return count
    }

    private func changedPixels(between before: NSBitmapImageRep, and after: NSBitmapImageRep) -> Int {
        guard before.pixelsWide == after.pixelsWide, before.pixelsHigh == after.pixelsHigh else { return 0 }
        return countPixels(before, after) { colorDifference($0, $1) > 0.08 }
    }

    private func luminance(_ color: NSColor) -> CGFloat? {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        func linear(_ component: CGFloat) -> CGFloat {
            component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent)
            + 0.0722 * linear(rgb.blueComponent)
    }

    private func contrastRatio(_ first: NSColor, _ second: NSColor) -> CGFloat? {
        contrastRatio(luminance(first), luminance(second))
    }

    private func contrastRatio(_ firstLuminance: CGFloat?, _ secondLuminance: CGFloat?) -> CGFloat? {
        guard let firstLuminance, let secondLuminance else { return nil }
        return (max(firstLuminance, secondLuminance) + 0.05) / (min(firstLuminance, secondLuminance) + 0.05)
    }

    private func highContrastChangedPixels(in full: NSBitmapImageRep, withoutContent blank: NSBitmapImageRep) -> Int {
        countPixels(full, blank) { ink, background in
            guard colorDifference(ink, background) > 0.08,
                let ratio = contrastRatio(ink.luminance, background.luminance)
            else { return false }
            return ratio >= 4.5
        }
    }

    @Test(arguments: [false, true])
    func `the panel lays out and draws its body text in each appearance`(dark: Bool) throws {
        let drawings = try drawings(dark: dark)
        #expect(drawings.bodyHeight > 0)
        #expect(drawings.bodyLayoutHeight > 0)

        let full = drawings.full
        if let path = ProcessInfo.processInfo.environment["HOVER_RENDER_DIR"] {
            let url = URL(filePath: path, directoryHint: .isDirectory)
                .appending(path: dark ? "hover-dark.png" : "hover-light.png")
            try #require(full.representation(using: .png, properties: [:])).write(to: url)
        }
        let changed = changedPixels(between: full, and: drawings.withoutBody)
        #expect(changed > 100)
    }

    @Test(arguments: [false, true])
    func `the drawn prose contrasts with the panel in each appearance`(dark: Bool) throws {
        let drawings = try drawings(dark: dark)
        let contrastingPixels = highContrastChangedPixels(in: drawings.full, withoutContent: drawings.withoutBody)
        #expect(contrastingPixels > 100)
    }

    @Test(arguments: [false, true])
    func `declaration text contrasts with its chip in each appearance`(dark: Bool) throws {
        let panel = try preparedPanel(dark: dark)
        let root = try #require(panel.contentViewForTests)
        let declaration = try #require(
            descendants(of: root, as: NSTextView.self).first { $0.string.contains("func greet") })
        let nameRange = (declaration.string as NSString).range(of: "greet")
        let color = try #require(
            declaration.textStorage?.attribute(.foregroundColor, at: nameRange.location, effectiveRange: nil))
        let foreground = try #require(color as? NSColor)
        let chip = try #require(
            sequence(first: declaration as NSView, next: \.superview).compactMap { $0 as? NSBox }.first)
        let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
        var ratio: CGFloat?
        appearance.performAsCurrentDrawingAppearance {
            ratio = contrastRatio(foreground, chip.fillColor)
        }
        #expect(try #require(ratio) >= 4.5)
    }

    @Test(arguments: sectionLabels, [false, true])
    func `section labels contrast with the panel in each appearance`(label: String, dark: Bool) throws {
        let drawings = try drawings(dark: dark)
        let blank = try #require(drawings.withoutLabel[label])
        #expect(highContrastChangedPixels(in: drawings.full, withoutContent: blank) > 20)
    }

    @Test(arguments: [false, true])
    func `the panel sizes to its content in each appearance`(dark: Bool) throws {
        let panel = try preparedPanel(dark: dark)
        let root = try #require(panel.contentViewForTests)
        let body = try #require(
            descendants(of: root, as: NSTextView.self).first { $0.string.contains("Summarizes a greeting") })
        let container = try #require(body.textContainer)
        let bodyHeight =
            body.textLayoutManager?.usageBoundsForTextContainer.height
            ?? body.layoutManager?.usedRect(for: container).height ?? 0
        let content = try #require(panel.laidOutContentHeightForTests)
        let height = try #require(panel.panelHeightForTests)
        #expect(abs(body.frame.height - bodyHeight) < 1)
        #expect(content > HoverPanelSizing.minHeight)
        #expect(content < HoverPanelSizing.maxHeight)
        #expect(abs(height - content) < 1)
    }

    @Test
    func `a long body is fully laid out within the scroll view`() throws {
        let appearance = try #require(NSAppearance(named: .aqua))
        let markdown = Self.markdown + "\n\n" + String(repeating: "Long details wrap inside the panel. ", count: 100)
        let document = HoverDocument.build(
            from: HoverContent(markdown: markdown, source: .languageServer), palette: .system)
        let panel = HoverDocPanel(ordersWindowIn: false)
        panel.prepareOffscreenForTests(document: document, appearance: appearance)
        let root = try #require(panel.contentViewForTests)
        let body = try #require(descendants(of: root, as: NSTextView.self).first { $0.string.contains("Long details") })
        let scrollView = try #require(body.enclosingScrollView)
        let container = try #require(body.textContainer)
        let usedHeight =
            body.textLayoutManager?.usageBoundsForTextContainer.height
            ?? body.layoutManager?.usedRect(for: container).height ?? 0
        #expect(panel.panelHeightForTests == HoverPanelSizing.maxHeight)
        #expect(scrollView.hasVerticalScroller)
        #expect(body.frame.width <= scrollView.contentSize.width + 1)
        #expect(body.frame.height >= usedHeight - 1)
        #expect(body.frame.height > scrollView.contentSize.height)
    }
}

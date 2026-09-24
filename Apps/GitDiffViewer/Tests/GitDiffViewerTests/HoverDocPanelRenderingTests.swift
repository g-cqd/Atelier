import AppKit
import AtelierSyntaxModel
import Foundation
import Testing

@testable import DiffRendering
@testable import DiffTextKit

@MainActor
@Suite struct HoverDocPanelRenderingTests {
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

    private func preparedPanel(dark: Bool) throws -> HoverDocPanel {
        let name: NSAppearance.Name = dark ? .darkAqua : .aqua
        let appearance = try #require(NSAppearance(named: name))
        let document = HoverDocument.build(
            from: HoverContent(markdown: Self.markdown, source: .languageServer), palette: .system)
        let panel = HoverDocPanel()
        panel.prepareOffscreenForTests(document: document, appearance: appearance)
        return panel
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

    private func colorDifference(_ lhs: NSColor, _ rhs: NSColor) -> CGFloat {
        guard let a = lhs.usingColorSpace(.deviceRGB), let b = rhs.usingColorSpace(.deviceRGB) else { return 0 }
        return max(
            max(abs(a.redComponent - b.redComponent), abs(a.greenComponent - b.greenComponent)),
            max(abs(a.blueComponent - b.blueComponent), abs(a.alphaComponent - b.alphaComponent)))
    }

    private func changedPixels(between before: NSBitmapImageRep, and after: NSBitmapImageRep) -> Int {
        guard before.pixelsWide == after.pixelsWide, before.pixelsHigh == after.pixelsHigh else { return 0 }
        var count = 0
        for y in 0 ..< before.pixelsHigh {
            for x in 0 ..< before.pixelsWide {
                guard let first = before.colorAt(x: x, y: y), let second = after.colorAt(x: x, y: y) else { continue }
                if colorDifference(first, second) > 0.08 { count += 1 }
            }
        }
        return count
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
        guard let firstLuminance = luminance(first), let secondLuminance = luminance(second) else { return nil }
        return (max(firstLuminance, secondLuminance) + 0.05) / (min(firstLuminance, secondLuminance) + 0.05)
    }

    private func highContrastChangedPixels(in full: NSBitmapImageRep, withoutContent blank: NSBitmapImageRep) -> Int {
        var count = 0
        for y in 0 ..< full.pixelsHigh {
            for x in 0 ..< full.pixelsWide {
                guard let ink = full.colorAt(x: x, y: y), let background = blank.colorAt(x: x, y: y),
                    colorDifference(ink, background) > 0.08,
                    let ratio = contrastRatio(ink, background)
                else { continue }
                if ratio >= 4.5 { count += 1 }
            }
        }
        return count
    }

    @Test(arguments: [false, true])
    func `the panel lays out and draws its body text in each appearance`(dark: Bool) throws {
        let panel = try preparedPanel(dark: dark)
        let root = try #require(panel.contentViewForTests)
        let body = try #require(
            descendants(of: root, as: NSTextView.self).first { $0.string.contains("Summarizes a greeting") })
        let container = try #require(body.textContainer)
        let layoutHeight =
            body.textLayoutManager?.usageBoundsForTextContainer.height
            ?? body.layoutManager?.usedRect(for: container).height ?? 0
        #expect(body.bounds.height > 0)
        #expect(layoutHeight > 0)

        let full = try bitmap(of: root)
        if let path = ProcessInfo.processInfo.environment["HOVER_RENDER_DIR"] {
            let url = URL(filePath: path, directoryHint: .isDirectory)
                .appending(path: dark ? "hover-dark.png" : "hover-light.png")
            try #require(full.representation(using: .png, properties: [:])).write(to: url)
        }
        let original = body.attributedString()
        body.textStorage?.setAttributedString(NSAttributedString())
        let withoutBody = try bitmap(of: root)
        body.textStorage?.setAttributedString(original)
        let changed = changedPixels(between: full, and: withoutBody)
        #expect(changed > 100)
    }

    @Test(arguments: [false, true])
    func `the drawn prose contrasts with the panel in each appearance`(dark: Bool) throws {
        let panel = try preparedPanel(dark: dark)
        let root = try #require(panel.contentViewForTests)
        let body = try #require(
            descendants(of: root, as: NSTextView.self).first { $0.string.contains("Summarizes a greeting") })
        let full = try bitmap(of: root)
        let original = body.attributedString()
        body.textStorage?.setAttributedString(NSAttributedString())
        let blank = try bitmap(of: root)
        body.textStorage?.setAttributedString(original)

        let contrastingPixels = highContrastChangedPixels(in: full, withoutContent: blank)
        #expect(contrastingPixels > 100)
    }

    @Test(arguments: ["PARAMETERS", "name"], [false, true])
    func `section labels contrast with the panel in each appearance`(label: String, dark: Bool) throws {
        let panel = try preparedPanel(dark: dark)
        let root = try #require(panel.contentViewForTests)
        let field = try #require(descendants(of: root, as: NSTextField.self).first { $0.stringValue == label })
        let full = try bitmap(of: root)
        let original = field.textColor
        field.textColor = .clear
        let blank = try bitmap(of: root)
        field.textColor = original

        #expect(highContrastChangedPixels(in: full, withoutContent: blank) > 20)
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
        let panel = HoverDocPanel()
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

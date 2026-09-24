import AppKit
import Foundation
import KittyStyle
import Testing

@testable import KittySyntax

/// Opt-in visual check that draws highlighted spans into bitmap files without an app window.
@Suite
struct OffscreenHighlightRenderTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ATELIER_RENDER_DIR"] != nil))
    @MainActor
    func `renders JSON and Swift grammar highlighting offscreen`() async throws {
        let directory = try #require(ProcessInfo.processInfo.environment["ATELIER_RENDER_DIR"])
        #expect(await LanguageHighlighter.ensureArtifacts(for: "json"))
        #expect(await LanguageHighlighter.ensureArtifacts(for: "swift"))
        let samples = [
            ("json", "json", "{\n  \"name\": \"Atelier\",\n  \"enabled\": true\n}"),
            ("swift", "swift", "struct Example {\n    let value = 42 // visible comment\n}")
        ]
        for (name, language, source) in samples {
            let session = LanguageHighlighter.makeSession(language: language)
            #expect(session.isGrammarBacked)
            let lines = session.highlightDocument(source: source)
            #expect(session.isGrammarBacked)
            let image = try #require(
                NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: 760, pixelsHigh: max(lines.count, 1) * 24 + 32,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                    isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            let context = try #require(NSGraphicsContext(bitmapImageRep: image))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.13, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: image.pixelsWide, height: image.pixelsHigh).fill()
            for (index, spans) in lines.enumerated() {
                let text = NSMutableAttributedString(string: "")
                for span in spans {
                    let color: NSColor =
                        switch span.style.fg {
                            case .rgb(r: let red, g: let green, b: let blue):
                                NSColor(
                                    calibratedRed: CGFloat(red) / 255, green: CGFloat(green) / 255,
                                    blue: CGFloat(blue) / 255, alpha: 1)
                            case .default, .indexed(_): .white
                        }
                    text.append(
                        NSAttributedString(
                            string: span.text,
                            attributes: [
                                .font: NSFont.monospacedSystemFont(
                                    ofSize: 15, weight: span.style.bold ? .semibold : .regular),
                                .foregroundColor: color
                            ]))
                }
                text.draw(at: NSPoint(x: 16, y: image.pixelsHigh - (index + 1) * 24 - 8))
            }
            context.flushGraphics()
            NSGraphicsContext.restoreGraphicsState()
            let data = try #require(image.representation(using: .png, properties: [:]))
            let path = URL(filePath: directory).appending(path: "\(name)-highlight.png")
            try data.write(to: path)
            #expect(data.count > 1_000)
        }
    }
}

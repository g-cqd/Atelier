import AtelierText
import Foundation
import KittyCodecs
import KittyFileTree
import KittyGit
import KittyRenderer
import KittySyntax
import KittyTerminal
import KittyWidgets
import KittyWorkspace
import Testing

@testable import KittyEditor

@Suite
struct KittyCodeConfigTests {
    @Test
    func `ColorRGB parses hex string`() {
        let parsed = ColorRGB(hex: "#1e2f3a")
        #expect(parsed != nil)
        #expect(parsed?.r == 0x1e)
        #expect(parsed?.g == 0x2f)
        #expect(parsed?.b == 0x3a)
    }

    @Test
    func `ColorRGB codable supports hex string`() throws {
        let json = "\"#abcdef\""
        let data = Data(json.utf8)
        let color = try JSONDecoder().decode(ColorRGB.self, from: data)
        #expect(color == ColorRGB(r: 0xab, g: 0xcd, b: 0xef))
    }

    @Test
    func `ColorRGB rejects invalid hex`() {
        #expect(ColorRGB(hex: "#zzz999") == nil)
        #expect(ColorRGB(hex: "#12345") == nil)
        #expect(ColorRGB(hex: "#1234567") == nil)
    }

    @Test
    func `ColorRGB parses 8 digit hex with alpha`() {
        let parsed = ColorRGB(hex: "#FF000080")
        #expect(parsed != nil)
        #expect(parsed?.r == 0xFF)
        #expect(parsed?.g == 0x00)
        #expect(parsed?.b == 0x00)
        #expect(parsed?.alpha == Double(0x80) / 255.0)
    }

    @Test
    func `ColorRGB 8 digit hex FF alpha is 1`() {
        let parsed = ColorRGB(hex: "#ABCDEFFF")
        #expect(parsed != nil)
        #expect(parsed?.r == 0xAB)
        #expect(parsed?.g == 0xCD)
        #expect(parsed?.b == 0xEF)
        #expect(parsed?.alpha == 1.0)
    }

    @Test
    func `ColorRGB 8 digit hex 00 alpha is 0`() {
        let parsed = ColorRGB(hex: "#ABCDEF00")
        #expect(parsed != nil)
        #expect(parsed?.alpha == 0.0)
    }

    @Test
    func `ColorRGB encodes 8 digit hex when alpha below 1`() throws {
        let color = ColorRGB(r: 0xFF, g: 0x00, b: 0x00, alpha: 0.5)
        let data = try JSONEncoder().encode(color)
        // swiftlint:disable:next force_unwrapping
        let hex = String(data: data, encoding: .utf8)!
        #expect(hex.contains("ff000080"))
    }

    @Test
    func `ColorRGB encodes 6 digit hex when alpha is 1`() throws {
        let color = ColorRGB(r: 0xAB, g: 0xCD, b: 0xEF)
        let data = try JSONEncoder().encode(color)
        // swiftlint:disable:next force_unwrapping
        let hex = String(data: data, encoding: .utf8)!
        #expect(hex.contains("abcdef"))
        #expect(!hex.contains("abcdefff"))
    }

    @Test
    func `ColorRGB codable roundtrips alpha`() throws {
        let original = ColorRGB(r: 0x11, g: 0x22, b: 0x33, alpha: 0.5)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ColorRGB.self, from: data)
        #expect(decoded.r == original.r)
        #expect(decoded.g == original.g)
        #expect(decoded.b == original.b)
        #expect(abs(decoded.alpha - original.alpha) < 0.01)
    }

    @Test
    func `ColorRGB HSB init produces correct red`() {
        let red = ColorRGB(hue: 0, saturation: 1, brightness: 1)
        #expect(red.r == 255)
        #expect(red.g == 0)
        #expect(red.b == 0)
        #expect(red.alpha == 1)
    }

    @Test
    func `ColorRGB HSB init produces correct green`() {
        let green = ColorRGB(hue: 1.0 / 3.0, saturation: 1, brightness: 1)
        #expect(green.r == 0)
        #expect(green.g == 255)
        #expect(green.b == 0)
    }

    @Test
    func `ColorRGB HSB init with alpha`() {
        let color = ColorRGB(hue: 0, saturation: 1, brightness: 1, alpha: 0.5)
        #expect(color.r == 255)
        #expect(color.alpha == 0.5)
    }

    @Test
    func `ColorRGB OKLCH init produces plausible values`() {
        let color = ColorRGB(lightness: 0.7, chroma: 0.15, hue: 150)
        #expect(color.g > color.r)
        #expect(color.alpha == 1)
    }

    @Test
    func `ColorRGB OKLCH init with alpha`() {
        let color = ColorRGB(lightness: 0.5, chroma: 0.1, hue: 30, alpha: 0.3)
        #expect(color.alpha == 0.3)
    }

    @Test
    func `ColorRGB OKLCH white`() {
        let white = ColorRGB(lightness: 1, chroma: 0, hue: 0)
        #expect(white.r == 255)
        #expect(white.g == 255)
        #expect(white.b == 255)
    }

    @Test
    func `ColorRGB OKLCH black`() {
        let black = ColorRGB(lightness: 0, chroma: 0, hue: 0)
        #expect(black.r == 0)
        #expect(black.g == 0)
        #expect(black.b == 0)
    }

    @Test
    func `Color overlay config decodes shorthand and alpha object`() throws {
        let shorthand = try JSONDecoder()
            .decode(
                ColorOverlayConfig.self,
                from: Data("\"#abcdef\"".utf8)
            )
        let alphaOverlay = try JSONDecoder()
            .decode(
                ColorOverlayConfig.self,
                from: Data("{\"color\":\"#112233\",\"alpha\":0.25}".utf8)
            )

        #expect(shorthand.color == ColorRGB(r: 0xab, g: 0xcd, b: 0xef))
        #expect(shorthand.alpha == 1)
        #expect(alphaOverlay.color == ColorRGB(r: 0x11, g: 0x22, b: 0x33))
        #expect(alphaOverlay.alpha == 0.25)
    }

    @Test
    func `Color overlay config decodes 8 digit hex shorthand`() throws {
        let overlay = try JSONDecoder()
            .decode(
                ColorOverlayConfig.self,
                from: Data("\"#FF000080\"".utf8)
            )
        #expect(overlay.color == ColorRGB(r: 0xFF, g: 0x00, b: 0x00))
        #expect(abs(overlay.alpha - Double(0x80) / 255.0) < 0.01)
    }

    @Test
    @MainActor
    func `Color scheme uses terminal default backgrounds`() {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        #expect(state.colorScheme.editorText.bg == .default)
        #expect(state.colorScheme.treeBg.bg == .default)
        #expect(state.colorScheme.statusBar.bg == .default)
    }
}

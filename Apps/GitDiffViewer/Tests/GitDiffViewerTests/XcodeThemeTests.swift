import AppKit
import DiffCore
import Testing

@testable import DiffComparison
@testable import DiffGit
@testable import DiffRendering
@testable import DiffTextKit

struct XcodeThemeTests {
    private static let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
            <key>DVTSourceTextBackground</key><string>0.1 0.2 0.3 1</string>
            <key>DVTLineSpacing</key><real>1.25</real>
            <key>DVTSourceTextSyntaxColors</key><dict>
                <key>xcode.syntax.plain</key><string>0.9 0.9 0.9 1</string>
                <key>xcode.syntax.keyword</key><string>1 0 0.5 1</string>
                <key>xcode.syntax.comment</key><string>0.5 0.5 0.5 0.5</string>
                <key>xcode.syntax.identifier.type</key><string>0 1 1 1</string>
            </dict>
            <key>DVTSourceTextSyntaxFonts</key><dict>
                <key>xcode.syntax.plain</key><string>Menlo-Regular - 13.0</string>
            </dict>
        </dict></plist>
        """

    @Test
    func `theme colors fonts and background are parsed`() throws {
        let theme = try XcodeTheme(data: Data(Self.plist.utf8))
        #expect(theme.background?.redComponent == 0.1)
        #expect(theme.color(for: "xcode.syntax.keyword")?.greenComponent == 0)
        #expect(theme.color(for: "xcode.syntax.comment")?.alphaComponent == 0.5)
        #expect(theme.color(for: "xcode.syntax.missing") == nil)
        #expect(theme.plainFont?.fontName == "Menlo-Regular")
        #expect(theme.plainFont?.pointSize == 13)
        #expect(theme.lineHeightMultiple == 1.25)
    }

    @Test(arguments: ["0.5 0.5", "a b c d", ""])
    func `malformed colors are ignored`(value: String) {
        #expect(XcodeTheme.color(from: value) == nil)
    }

    @Test
    func `a palette built from a theme maps the diff colors and falls back for missing keys`() throws {
        let theme = try XcodeTheme(data: Data(Self.plist.utf8))
        let palette = DiffPalette(theme: theme)
        #expect(palette.textColor.redComponent == 0.9)
        #expect(palette.background.blueComponent == 0.3)
        #expect(palette.font.fontName == "Menlo-Regular")
        #expect(palette.color(for: .keyword).redComponent == 1)
        #expect(palette.color(for: .type).greenComponent == 1)
        #expect(palette.color(for: .string) == palette.textColor)
        #expect(palette.lineHeightMultiple == 1.25)
    }

    @Test
    func `a taller line keeps its multiple and raises the text by half the extra space`() throws {
        let natural = DiffPalette.system.defaultLineHeight
        let rendered = DiffRenderer.render(
            oldText: "a\nb\n", newText: "a\nc\n", language: .plain, lineHeightMultiple: 1.5)
        let text = try #require(rendered.unified)
        let style = try #require(
            text.attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)

        #expect(style.lineHeightMultiple == 1.5)
        // TextKit puts every point of the extra space above the glyphs, so the panes raise them by half of it.
        #expect(text.baselineOffset == 0.25 * natural)
        #expect(text.attributed.attribute(.baselineOffset, at: 0, effectiveRange: nil) == nil)
    }

    @Test
    func `the natural line height leaves the text where it is`() throws {
        let rendered = DiffRenderer.render(oldText: "a\n", newText: "b\n", language: .plain)
        let text = try #require(rendered.unified)
        let style = try #require(
            text.attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)

        #expect(style.lineHeightMultiple == 1)
        #expect(text.baselineOffset == 0)
    }

    @Test
    func `wrap width follows the column and the font's advance`() {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let advance = ("0" as NSString).size(withAttributes: [.font: font]).width
        #expect(DiffPalette.wrapWidth(column: 80, font: font, padding: 6) == 80 * advance + 12)
    }
}

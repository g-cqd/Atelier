import AppKit
import AtelierSyntaxModel
import Foundation
import Testing

@testable import DiffRendering

@Suite struct HoverDocumentTests {
    /// A regression test for the invisible-prose bug: `AttributedString(markdown:)` leaves `.foregroundColor`
    /// unset for plain runs, which on the hover panel's vibrant `.behindWindow` material rendered as blank text
    /// even though the summary had genuinely been resolved (``renderProse`` in `HoverDocument`). Every run of the
    /// built summary must carry an explicit color so it never blends into the panel's own glass.
    @Test func summaryProseAlwaysCarriesAnExplicitForegroundColor() throws {
        let content = HoverContent(
            markdown: """
                ```swift
                struct CameraConfiguration
                ```

                A value type describing how a capture session should be configured.
                """,
            source: .docIndex)
        let document = HoverDocument.build(from: content, palette: .system)
        let summary = try #require(document.summary)
        var sawUnset = false
        summary.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: summary.length)) {
            value, _, _ in
            if value == nil { sawUnset = true }
        }
        #expect(!sawUnset)
        #expect(summary.string == "A value type describing how a capture session should be configured.")
    }

    /// The declaration chip's backing comes from the pane's own palette, not the panel's vibrancy material: a
    /// theme's role colors are chosen to read against the pane they render in, so the panel copies that same
    /// background behind the declaration (and any candidate declarations) rather than leaving it to whatever
    /// light/dark appearance the panel's own glass happens to land on.
    @Test func buildCarriesTheChipBackgroundFromThePalette() throws {
        let content = HoverContent(
            markdown: """
                ```swift
                struct CameraConfiguration
                ```

                A value type describing how a capture session should be configured.
                """,
            source: .docIndex)
        let palette = DiffPalette.system
        let document = HoverDocument.build(from: content, palette: palette)
        let chipBackground = try #require(document.chipBackground)
        #expect(
            chipBackground.usingColorSpace(.sRGB) == palette.background.withAlphaComponent(0.94).usingColorSpace(.sRGB))
    }

    /// A regression test for the Helvetica-leaking-into-prose bug: `AttributedString(markdown:)` records bold and
    /// italic as `inlinePresentationIntent`, never as a font, and the bridge to `NSAttributedString` has nothing
    /// of its own to fall back to -- a run with no `.font` attribute draws in `NSTextView`'s hardcoded default,
    /// Helvetica 12, not the system font, dropping the bold/italic styling along with it. Every run of a built
    /// summary must carry an explicit `NSFont` whose family matches the system font's own, never Helvetica, and
    /// bold/italic text must carry the matching symbolic trait.
    @Test func summaryProseAlwaysCarriesAnExplicitSystemFont() throws {
        let content = HoverContent(
            markdown: """
                ```swift
                struct CameraConfiguration
                ```

                A **strongly emphasized** value and an *emphasized* one, plus `inline code`.
                """,
            source: .docIndex)
        let document = HoverDocument.build(from: content, palette: .system)
        let summary = try #require(document.summary)

        let systemFamily = NSFont.systemFont(ofSize: 12).familyName
        var sawFontlessRun = false
        var sawBold = false
        var sawItalic = false
        var sawMonospaced = false
        summary.enumerateAttribute(.font, in: NSRange(location: 0, length: summary.length)) { value, range, _ in
            guard let font = value as? NSFont else {
                sawFontlessRun = true
                return
            }
            let substring = (summary.string as NSString).substring(with: range)
            if font.fontDescriptor.symbolicTraits.contains(.bold) {
                sawBold = true
                #expect(substring == "strongly emphasized")
            }
            if font.fontDescriptor.symbolicTraits.contains(.italic) {
                sawItalic = true
                #expect(substring == "emphasized")
            }
            if !font.fontDescriptor.symbolicTraits.contains([.bold, .italic]) {
                #expect(font.familyName == systemFamily || font.fontDescriptor.symbolicTraits.contains(.monoSpace))
            }
            if substring == "inline code" {
                sawMonospaced = true
                #expect(font.familyName != "Helvetica")
            }
        }
        #expect(!sawFontlessRun)
        #expect(sawBold)
        #expect(sawItalic)
        #expect(sawMonospaced)
    }

    /// An underscored compiler attribute is stripped from the declaration before it reaches the panel, matching
    /// Xcode's own Quick Help; a public attribute is kept.
    @Test func declarationDropsUnderscoredAttributesButKeepsPublicOnes() throws {
        let content = HoverContent(
            markdown: """
                ```swift
                @_originallyDefinedIn(module: "SwiftUICore", macOS 15.0)
                @MainActor
                struct StateObject<ObjectType>
                ```

                A property wrapper.
                """,
            source: .languageServer)
        let document = HoverDocument.build(from: content, palette: .system)
        let declaration = try #require(document.declaration)
        #expect(!declaration.string.contains("_originallyDefinedIn"))
        #expect(declaration.string.contains("@MainActor"))
    }
}

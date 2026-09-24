import AppKit
import AtelierSyntaxModel
import Foundation
import Testing

@testable import DiffRendering

@Suite struct HoverDocumentTests {
    /// Uncolored text would blend into the panel's vibrant material.
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

    /// A theme's role colors read against the pane's own background, not against the panel's glass.
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

    @Test
    func `adding diagnostics keeps every other field of the document`() {
        let declaration = NSAttributedString(string: "func run()")
        let summary = NSAttributedString(string: "Runs.")
        let discussion = NSAttributedString(string: "At once.")
        let blocks: [HoverDocument.Block] = [.paragraph(discussion)]
        let returns = NSAttributedString(string: "Nothing.")
        let parameter = HoverDocument.Field(name: "speed", text: NSAttributedString(string: "How fast."))
        let candidate = HoverDocument.Candidate(
            declaration: NSAttributedString(string: "func run(fast: Bool)"), summary: nil)
        let document = HoverDocument(
            title: "run()", declaration: declaration, summary: summary, discussion: blocks, parameters: [parameter],
            returns: returns, provenance: .docIndex, extraCandidates: [candidate],
            diagnostics: [HoverDocument.DiagnosticEntry(severity: .note, message: "first", tool: "swiftlint")],
            chipBackground: .textBackgroundColor)

        let joined = document.adding(diagnostics: [
            HoverDocument.DiagnosticEntry(severity: .warning, message: "second", tool: "periphery")
        ])

        #expect(joined.declaration === declaration)
        #expect(joined.summary === summary)
        #expect(joined.title == "run()")
        let joinedParagraph: NSAttributedString? =
            if case .paragraph(let text)? = joined.discussion.first { text } else { nil }
        #expect(joined.discussion.count == 1)
        #expect(joinedParagraph === discussion)
        #expect(joined.returns === returns)
        #expect(joined.parameters.map(\.name) == ["speed"])
        #expect(joined.parameters.first?.text === parameter.text)
        #expect(joined.provenance == .docIndex)
        #expect(joined.extraCandidates.first?.declaration === candidate.declaration)
        #expect(joined.diagnostics.map(\.message) == ["first", "second"])
        #expect(joined.chipBackground === NSColor.textBackgroundColor)
    }

    /// HOVER-06: the resolver joins a row's findings to the built document, and the declaration keeps its chip.
    @Test
    func `a declaration joined by a row's findings keeps the pane's chip background`() throws {
        let content = HoverContent(
            markdown: "```swift\nstruct CameraConfiguration\n```\n\nA configuration.", source: .docIndex)
        let palette = DiffPalette.system
        let finding = HoverDocument.DiagnosticEntry(severity: .warning, message: "unused", tool: "periphery")

        let document = HoverDocument.build(from: content, palette: palette).adding(diagnostics: [finding])

        let chipBackground = try #require(document.chipBackground)
        #expect(
            chipBackground.usingColorSpace(.sRGB) == palette.background.withAlphaComponent(0.94).usingColorSpace(.sRGB))
    }

    /// A fontless run would draw in Helvetica 12; bold and italic runs also carry the matching symbolic trait.
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

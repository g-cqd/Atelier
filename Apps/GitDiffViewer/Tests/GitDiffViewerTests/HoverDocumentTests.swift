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

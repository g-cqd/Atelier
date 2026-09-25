import AppKit
import AtelierSyntaxModel
import Foundation
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// HOVER-20 criterion 4: a Relationships section lists what the symbol conforms to, read from the inheritance clause of
/// the declaration every tier gives.
struct HoverRelationshipsTests {
    private static let conformsTo = HoverRelationship.Kind.conformsTo
    private static let inheritsFrom = HoverRelationship.Kind.inheritsFrom

    /// Declarations as the tiers give them, the SDK's and the language server's as sourcekit-lsp prints them and the
    /// doc-comment tier's as it cuts a declaration before its body, with the groups each makes.
    static let cases: [(String, [HoverRelationship])] = [
        ("@frozen struct Bool : Sendable", [HoverRelationship(kind: conformsTo, names: ["Sendable"])]),
        (
            "@_nonSendable(_assumed) struct DirectoryEnumerationOptions : OptionSet, @unchecked Sendable",
            [HoverRelationship(kind: conformsTo, names: ["OptionSet", "Sendable"])]
        ),
        (
            "@_nonSendable(_assumed) class NSView : NSResponder, NSAnimatablePropertyContainer, NSDraggingDestination",
            [
                HoverRelationship(kind: inheritsFrom, names: ["NSResponder"]),
                HoverRelationship(kind: conformsTo, names: ["NSAnimatablePropertyContainer", "NSDraggingDestination"])
            ]
        ),
        (
            "final class Model: Sendable, Identifiable",
            [HoverRelationship(kind: conformsTo, names: ["Sendable", "Identifiable"])]
        ),
        ("public protocol Store: AnyObject, Sendable", [HoverRelationship(kind: inheritsFrom, names: ["Sendable"])]),
        ("enum Kind: String, CaseIterable", [HoverRelationship(kind: conformsTo, names: ["CaseIterable"])]),
        (
            "struct Box<T: Equatable>: Equatable, Codable where T: Hashable",
            [HoverRelationship(kind: conformsTo, names: ["Equatable", "Codable"])]
        ),
        (
            "extension Array: Loadable where Element: Loadable",
            [HoverRelationship(kind: conformsTo, names: ["Loadable"])]
        ),
        (
            "struct Handle: ~Copyable, Reading & Writing",
            [HoverRelationship(kind: conformsTo, names: ["Reading", "Writing"])]
        ),
        ("protocol Sequence<Element>", []),
        ("class JSONDecoder", []),
        ("class var `default`: FileManager { get }", []),
        ("static func load(from url: URL) throws -> Config", []),
        ("let retryCount: Int", [])
    ]

    @Test(arguments: cases)
    func `a declaration's inheritance clause makes Quick Help's groups`(
        declaration: String, expected: [HoverRelationship]
    ) {
        #expect(HoverRelationships.relationships(fromDeclaration: declaration) == expected)
    }

    @Test
    func `the SDK's Bool document conforms to what its declaration says`() {
        let document = HoverDocument.build(
            from: HoverContent(markdown: HoverFixtures.sdkBool, source: .sdk), palette: .system)
        #expect(document.relationships == [HoverRelationship(kind: .conformsTo, names: ["Sendable"])])
    }
}

@MainActor
struct HoverRelationshipsPanelTests {
    private static func shownTexts(of document: HoverDocument) throws -> [String] {
        let panel = HoverDocPanel(ordersWindowIn: false)
        panel.prepareOffscreenForTests(document: document, appearance: try #require(NSAppearance(named: .aqua)))
        panel.scrollThroughDiscussion()
        return panel.shownBlockViews.compactMap { ($0 as? NSTextView)?.string }
    }

    @Test
    func `the Relationships section follows the discussion, a titled group of names each`() throws {
        let document = HoverDocument.build(
            from: HoverContent(markdown: HoverFixtures.sdkBool, source: .sdk), palette: .system)

        let texts = try Self.shownTexts(of: document)

        #expect(texts.first == "Overview")
        #expect(Array(texts.suffix(3)) == ["Relationships", "Conforms To", "Sendable"])
    }

    @Test
    func `a declaration with nothing else shows no Relationships section`() throws {
        let document = HoverDocument.build(
            from: HoverContent(markdown: "```swift\nstruct Config : Codable\n```\n", source: .languageServer),
            palette: .system)
        #expect(!document.relationships.isEmpty)

        #expect(try Self.shownTexts(of: document).isEmpty)
    }
}

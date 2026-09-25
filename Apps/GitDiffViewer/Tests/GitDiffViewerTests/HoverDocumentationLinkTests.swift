import AppKit
import AtelierSyntaxModel
import Foundation
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// HOVER-20 criterion 5: a system symbol offers "Open in Developer Documentation", which opens its page in Apple's
/// developer documentation through the panel's own link handling.
@MainActor
struct HoverDocumentationLinkTests {
    @MainActor
    private final class OpenedLinks {
        private(set) var urls: [URL] = []
        func record(_ url: URL) { urls.append(url) }
    }

    private static func document(page: HoverContent.DocumentationPage?, markdown: String) -> HoverDocument {
        HoverDocument.build(
            from: HoverContent(markdown: markdown, source: .sdk, documentationPage: page), palette: .system)
    }

    /// The panel's text views that show "Open in Developer Documentation", with no hidden ancestor.
    private static func linkViews(of panel: HoverDocPanel) throws -> [NSTextView] {
        let root = try #require(panel.contentViewForTests)
        var found: [NSTextView] = []
        var pending = [root]
        while let view = pending.popLast() {
            pending.append(contentsOf: view.subviews)
            if let textView = view as? NSTextView, !textView.isHiddenOrHasHiddenAncestor,
                textView.string == "Open in Developer Documentation"
            {
                found.append(textView)
            }
        }
        return found
    }

    @Test(arguments: [
        (
            HoverContent.DocumentationPage(module: "Swift", path: ["Bool"]),
            "https://developer.apple.com/documentation/swift/bool"
        ),
        (
            HoverContent.DocumentationPage(module: "Foundation", path: ["FileManager", "contents(atPath:)"]),
            "https://developer.apple.com/documentation/foundation/filemanager/contents(atpath:)"
        ),
        (
            HoverContent.DocumentationPage(module: "Swift", path: ["String", "Encoding", "utf8"]),
            "https://developer.apple.com/documentation/swift/string/encoding/utf8"
        )
    ])
    func `a page's address is its module and path, lowercased, under Apple's documentation`(
        page: HoverContent.DocumentationPage, address: String
    ) {
        #expect(HoverDocument.documentationURL(for: page)?.absoluteString == address)
    }

    @Test
    func `a system symbol's panel opens its page from the link under it`() throws {
        let opened = OpenedLinks()
        let panel = HoverDocPanel(openLink: { opened.record($0) }, ordersWindowIn: false)
        let document = Self.document(
            page: HoverContent.DocumentationPage(module: "Foundation", path: ["FileManager", "default"]),
            markdown: HoverFixtures.sdkUndocumentedProperty)
        panel.prepareOffscreenForTests(document: document, appearance: try #require(NSAppearance(named: .aqua)))

        let linkView = try #require(try Self.linkViews(of: panel).first)
        let link = try #require(linkView.textStorage?.attribute(.link, at: 0, effectiveRange: nil))
        _ = panel.linkDelegate.textView(linkView, clickedOnLink: link, at: 0)

        #expect(
            opened.urls.map(\.absoluteString) == [
                "https://developer.apple.com/documentation/foundation/filemanager/default"
            ])
    }

    @Test
    func `a symbol with no page shows no link`() throws {
        let panel = HoverDocPanel(ordersWindowIn: false)
        panel.prepareOffscreenForTests(
            document: Self.document(page: nil, markdown: HoverFixtures.sdkBool),
            appearance: try #require(NSAppearance(named: .aqua)))

        #expect(try Self.linkViews(of: panel).isEmpty)
    }

    @Test
    func `a row's findings keep the page of the documentation they join`() {
        let document = Self.document(
            page: HoverContent.DocumentationPage(module: "Swift", path: ["Bool"]), markdown: HoverFixtures.sdkBool)
        let joined = document.adding(diagnostics: [.init(severity: .warning, message: "Unused", tool: "swiftlint")])
        #expect(joined.documentationURL == document.documentationURL)
        #expect(joined.relationships == document.relationships)
    }
}

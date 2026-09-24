import AppKit
import AtelierDocIndex
import AtelierSyntaxModel
import Foundation
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// HOVER-20: a hover reads as Xcode's Quick Help, from every tier: the symbol's name, its abstract, its declaration in a
/// box, a divider, then the discussion under an Overview heading, block by block.
@MainActor
@Suite struct HoverQuickHelpTests {
    private static func kind(_ block: HoverDocument.Block) -> String {
        switch block {
            case .paragraph: "paragraph"
            case .heading(let level, _): "heading \(level)"
            case .code: "code"
            case .list(let ordered, _, _): ordered ? "numbered list" : "bullet list"
            case .quote: "quote"
            case .rule: "rule"
        }
    }

    private static func codeText(in blocks: [HoverDocument.Block]) -> [String] {
        blocks.compactMap { if case .code(let code) = $0 { code.string } else { nil } }
    }

    private static func build(_ markdown: String, source: HoverContent.Source) -> HoverDocument {
        HoverDocument.build(from: HoverContent(markdown: markdown, source: source), palette: .system)
    }

    // MARK: The document

    @Test
    func `the Bool document's head is its name, its abstract and its declaration`() {
        let document = Self.build(HoverFixtures.sdkBool, source: .sdk)
        #expect(document.title == "Bool")
        #expect(document.summary?.string == "A value type whose instances are either true or false.")
        #expect(document.declaration?.string == "@frozen\nstruct Bool : Sendable")
        #expect(document.discussion.map(Self.kind).count == 9)
    }

    /// Quick Help shows a declaration's attributes above it, one to a line, their arguments whole; an attribute on a
    /// parameter's type stays where it is. The title still reads the declared name.
    @Test(arguments: [
        ("@frozen struct Bool : Sendable", "@frozen\nstruct Bool : Sendable"),
        (
            "@available(macOS 14, *) @MainActor public func run(_ body: @escaping () -> Void)",
            "@available(macOS 14, *)\n@MainActor\npublic func run(_ body: @escaping () -> Void)"
        ),
        (
            "@MainActor @preconcurrency\n@frozen\nstruct StateObject<ObjectType>",
            "@MainActor\n@preconcurrency\n@frozen\nstruct StateObject<ObjectType>"
        ),
        (
            #"@available(*, deprecated, message: "Use run(_:) (the async one)") func start()"#,
            #"@available(*, deprecated, message: "Use run(_:) (the async one)")\#nfunc start()"#
        ),
        ("func contains(_ element: Element) -> Bool", "func contains(_ element: Element) -> Bool")
    ])
    func `a declaration's attributes each go on a line of their own`(declaration: String, shown: String) {
        let document = Self.build("```swift\n\(declaration)\n```\n\nDoes it.", source: .languageServer)
        #expect(document.declaration?.string == shown)
        #expect(document.title == HoverDeclarationName.name(fromDeclaration: declaration))
    }

    @Test
    func `a code block is colored as Swift`() throws {
        let document = Self.build(HoverFixtures.sdkBool, source: .sdk)
        let code = try #require(
            document.discussion.compactMap { if case .code(let code) = $0 { code } else { nil } }.first)
        var colors: Set<NSColor> = []
        code.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: code.length)) { value, _, _ in
            if let color = value as? NSColor { colors.insert(color) }
        }
        let keyword = code.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        let name = code.attribute(.foregroundColor, at: 4, effectiveRange: nil) as? NSColor
        #expect(colors.count > 2)
        #expect(keyword != name, "`var` and `godotHasArrived` share a color")
    }

    @Test
    func `headings of levels 1 to 3 are each larger than the last and than the prose`() {
        let document = Self.build(HoverFixtures.everyBlockKind, source: .languageServer)
        let sizes = document.discussion.compactMap { block -> CGFloat? in
            guard case .heading(_, let text) = block else { return nil }
            return (text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize
        }
        #expect(sizes.count == 3)
        #expect(sizes == sizes.sorted(by: >))
        #expect(Set(sizes).count == 3)
        #expect(sizes.allSatisfy { $0 > HoverTypography.bodySize })
    }

    @Test(arguments: [
        ("@frozen struct Bool : Sendable", "Bool"),
        ("static func load(from url: URL) throws -> Config", "load(from:)"),
        ("func contains(_ element: Element) -> Bool", "contains(_:)"),
        ("func map<T>(_ transform: (Element) throws -> T) rethrows -> [T]", "map(_:)"),
        ("class var `default`: FileManager { get }", "default"),
        ("let retryCount: Int", "retryCount"),
        ("init?(rawValue: String)", "init(rawValue:)"),
        ("subscript(index: Int) -> Element { get }", "subscript(_:)"),
        ("static func <= (lhs: Self, rhs: Self) -> Bool", "<=(_:_:)"),
        ("case some(Wrapped)", "some(_:)"),
        (
            "@MainActor @preconcurrency\n@frozen\nstruct StateObject<ObjectType> where ObjectType: ObservableObject",
            "StateObject"
        ),
        ("@available(macOS 10.15, *) final class Coordinator", "Coordinator")
    ])
    func `the title is the declared name`(declaration: String, name: String) {
        #expect(HoverDeclarationName.name(fromDeclaration: declaration) == name)
    }

    @Test
    func `a declaration that names nothing has no title`() {
        #expect(HoverDeclarationName.name(fromDeclaration: "let (a, b) = pair") == nil)
        #expect(HoverDeclarationName.name(fromDeclaration: "") == nil)
    }

    // MARK: Each tier

    @Test
    func `the language server's documented function reads as its blocks`() {
        let document = Self.build(HoverFixtures.languageServerDocumentedFunction, source: .languageServer)
        #expect(document.title == "load(from:)")
        #expect(document.summary?.string == "Loads the configuration.")
        #expect(document.returns?.string == "The configuration.")
        #expect(document.parameters.map(\.name) == ["url"])
        #expect(document.parameters.map(\.text.string) == ["Where the file is."])
        #expect(document.discussion.map(Self.kind) == ["paragraph", "code", "heading 2"])
        #expect(
            Self.codeText(in: document.discussion) == [
                "let config = try load(from: url)\nif config.retryCount > 0 {\n    print(config)\n}"
            ])
    }

    /// The doc-comment tier's own answer, from its provider over a `///` comment, not a transcription of it.
    @Test
    func `the doc comment tier's answer reads as its blocks`() async throws {
        let source = """
            /// Parses a manifest.
            ///
            /// Reads every line:
            ///
            /// ```swift
            /// for line in lines {
            ///     parse(line)
            /// }
            /// ```
            ///
            /// # Errors
            ///
            /// Throws on a bad line.
            func parseManifest(_ text: String) throws {}

            func use() { try? parseManifest("") }
            """
        let index = DocCommentIndex()
        try await index.update(files: [DocIndexFile(uri: "file:///Manifest.swift", content: source)])
        let line = source.components(separatedBy: "\n").count - 1
        let query = HoverQuery(
            documentURI: "file:///Manifest.swift", content: source, line: line,
            utf16Column: "func use() { try? parseMan".utf16.count)
        let content = try #require(try await DocIndexHoverProvider(index: index).hover(query))

        let document = HoverDocument.build(from: content, palette: .system)
        #expect(document.title == "parseManifest(_:)")
        #expect(document.summary?.string == "Parses a manifest.")
        #expect(document.discussion.map(Self.kind) == ["paragraph", "code", "heading 1", "paragraph"])
        #expect(Self.codeText(in: document.discussion) == ["for line in lines {\n    parse(line)\n}"])
    }

    // MARK: The panel

    private func preparedPanel(for document: HoverDocument) throws -> (HoverDocPanel, NSView) {
        let panel = HoverDocPanel(ordersWindowIn: false)
        panel.prepareOffscreenForTests(document: document, appearance: try #require(NSAppearance(named: .aqua)))
        let root = try #require(panel.contentViewForTests)
        root.layoutSubtreeIfNeeded()
        return (panel, root)
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

    /// The text of every piece of text the panel shows, with the view showing it.
    private func shownTexts(under root: NSView) -> [(text: String, view: NSView)] {
        let views =
            descendants(of: root, as: NSTextView.self).map { ($0.string, $0 as NSView) }
            + descendants(of: root, as: NSTextField.self).map { ($0.stringValue, $0 as NSView) }
        return views.filter { !$0.0.isEmpty && !$0.1.isHiddenOrHasHiddenAncestor }
    }

    @Test
    func `the Bool panel lays out its head and every block top to bottom`() throws {
        let (panel, root) = try preparedPanel(for: Self.build(HoverFixtures.sdkBool, source: .sdk))
        let shown = shownTexts(under: root)
        func view(startingWith prefix: String) throws -> NSView {
            try #require(shown.first { $0.text.hasPrefix(prefix) }?.view, "nothing shows \(prefix)")
        }
        let divider = try #require(
            descendants(of: root, as: NSBox.self).first { $0.boxType == .separator && !$0.isHiddenOrHasHiddenAncestor })
        let ordered: [NSView] = [
            try #require(shown.first { $0.text == "Bool" }?.view), try view(startingWith: "A value type"),
            try view(startingWith: "@frozen\nstruct Bool"), divider, try view(startingWith: "Overview"),
            try view(startingWith: "Bool represents"), try view(startingWith: "var godotHasArrived"),
            try view(startingWith: "Swift uses only"), try view(startingWith: "For example"),
            try view(startingWith: "var i = 5"), try view(startingWith: "The correct approach"),
            try view(startingWith: "while i != 0"), try view(startingWith: "Using Imported Boolean values"),
            try view(startingWith: "The C bool")
        ]
        // The root is not flipped: a view further down the panel has smaller y.
        let frames = ordered.map { $0.convert($0.bounds, to: root) }
        for (index, (above, below)) in zip(frames, frames.dropFirst()).enumerated() {
            #expect(above.minY >= below.maxY - 0.5, "view \(index) overlaps or follows view \(index + 1)")
        }
        #expect(shown.first { $0.text.hasPrefix("var i = 5") }?.text.contains("while i {\n    print(i)\n") == true)
        #expect(shown.filter { $0.text == "Bool" }.count == 1)

        // Taller than the panel may be: it takes its greatest height and its body scrolls.
        let scrollView = try #require(ordered[5].enclosingScrollView)
        #expect(panel.panelHeightForTests == HoverPanelSizing.maxHeight)
        #expect(scrollView.hasVerticalScroller)
        #expect(scrollView.documentView.map { $0.frame.height > scrollView.contentSize.height } == true)
    }
}

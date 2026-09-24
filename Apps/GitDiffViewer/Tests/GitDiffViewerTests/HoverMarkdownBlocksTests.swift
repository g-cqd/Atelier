import Foundation
import Testing

@testable import DiffRendering

/// HOVER-20: the discussion parses into its blocks, each kept apart, instead of one run of prose.
@Suite struct HoverMarkdownBlocksTests {
    /// A block's kind, with what tells same-kind blocks apart: a heading's level, a fence's language, a list's shape.
    private static func kind(_ block: HoverMarkdownBlock) -> String {
        switch block {
            case .paragraph: "paragraph"
            case .heading(let level, _): "heading \(level)"
            case .code(let language, _): language.map { "code \($0)" } ?? "code"
            case .list(let ordered, let start, let items):
                ordered ? "numbered list from \(start), \(items.count) items" : "bullet list, \(items.count) items"
            case .quote: "quote"
            case .thematicBreak: "rule"
        }
    }

    /// A block's text as the panel shows it, a container's blocks one per line.
    private static func text(_ block: HoverMarkdownBlock) -> String {
        switch block {
            case .paragraph(let text), .heading(_, let text): String(text.characters)
            case .code(_, let text): text
            case .list(_, _, let items): items.flatMap { $0 }.map(text).joined(separator: "\n")
            case .quote(let blocks): blocks.map(text).joined(separator: "\n")
            case .thematicBreak: ""
        }
    }

    private static func code(in blocks: [HoverMarkdownBlock]) -> [String] {
        blocks.compactMap { if case .code(_, let text) = $0 { text } else { nil } }
    }

    private static var boolDiscussion: [HoverMarkdownBlock] {
        HoverMarkdownBlock.parse(HoverMarkdownStructurer.structure(HoverFixtures.sdkBool).discussion ?? "")
    }

    private static var syntheticDiscussion: [HoverMarkdownBlock] {
        HoverMarkdownBlock.parse(HoverMarkdownStructurer.structure(HoverFixtures.everyBlockKind).discussion ?? "")
    }

    @Test
    func `the Bool discussion parses into its paragraphs, code blocks and heading, in order`() {
        #expect(
            Self.boolDiscussion.map(Self.kind) == [
                "paragraph", "code", "paragraph", "paragraph", "code", "paragraph", "code", "heading 1", "paragraph"
            ])
    }

    @Test
    func `every code block of the Bool discussion keeps its lines and indentation exactly`() {
        #expect(
            Self.code(in: Self.boolDiscussion) == [
                """
                var godotHasArrived = false

                let numbers = 1...5
                let containsTen = numbers.contains(10)
                print(containsTen)
                // Prints "false"

                let (a, b) = (100, 101)
                let aFirst = a < b
                print(aFirst)
                // Prints "true"
                """,
                """
                var i = 5
                while i {
                    print(i)
                    i -= 1
                }
                // error: Cannot convert value of type 'Int' to expected condition type 'Bool'
                """,
                """
                while i != 0 {
                    print(i)
                    i -= 1
                }
                """
            ])
    }

    @Test
    func `no block of the Bool discussion runs into the next`() {
        let texts = Self.boolDiscussion.map(Self.text)
        for (current, next) in zip(texts, texts.dropFirst()) {
            #expect(!current.contains(next.prefix(24)), "\(current.suffix(40)) runs into \(next.prefix(24))")
        }
        #expect(
            texts.first == "Bool represents Boolean values in Swift. Create instances of Bool by using one of the "
                + "Boolean literals true or false, or by assigning the result of a Boolean method or operation to a "
                + "variable or constant.")
        #expect(texts.last?.hasPrefix("The C bool and Boolean types") == true)
    }

    @Test
    func `every block kind parses, each block apart from the next`() {
        #expect(
            Self.syntheticDiscussion.map(Self.kind) == [
                "paragraph", "heading 1", "heading 2", "heading 3", "code swift", "code", "code objc",
                "bullet list, 2 items", "numbered list from 3, 2 items", "quote", "rule", "paragraph"
            ])
        #expect(
            Self.code(in: Self.syntheticDiscussion) == [
                "let config = try load(from: url)\n\nif config.isValid {\n    print(config)\n}",
                "let indented = true\n    nested()",
                "[object message];"
            ])
    }

    @Test
    func `a list item keeps its own code block`() throws {
        let list = try #require(
            Self.syntheticDiscussion.first { if case .list(false, _, _) = $0 { true } else { false } })
        guard case .list(_, _, let items) = list else { return }
        #expect(items.map { $0.map(Self.kind) } == [["paragraph"], ["paragraph", "code swift"]])
        #expect(Self.code(in: items[1]) == ["let x = 1"])
    }

    @Test
    func `a paragraph keeps inline code, emphasis, strong and links`() throws {
        let blocks = HoverMarkdownBlock.parse(
            "Loads *quickly* and **safely**, with `inline code` and [a link](https://example.com/load).")
        guard case .paragraph(let text)? = blocks.first, blocks.count == 1 else {
            Issue.record("expected one paragraph, got \(blocks.map(Self.kind))")
            return
        }
        func intent(of word: String) -> InlinePresentationIntent? {
            text.range(of: word).flatMap { text[$0].runs.first?.inlinePresentationIntent }
        }
        #expect(intent(of: "quickly") == .emphasized)
        #expect(intent(of: "safely") == .stronglyEmphasized)
        #expect(intent(of: "inline code") == .code)
        let link = try #require(text.range(of: "a link"))
        #expect(text[link].runs.first?.link == URL(string: "https://example.com/load"))
    }

    @Test
    func `blank markdown has no blocks`() {
        #expect(HoverMarkdownBlock.parse("").isEmpty)
        #expect(HoverMarkdownBlock.parse(" \n\n ").isEmpty)
    }
}

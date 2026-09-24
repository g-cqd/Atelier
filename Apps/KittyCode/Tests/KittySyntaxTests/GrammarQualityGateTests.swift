import AtelierParser
import Testing

@testable import KittySyntax

/// A grammar session highlights a document from its parse only while ERROR nodes cover less than
/// `LanguageHighlighter.maxErrorBytePercent` percent of the document's bytes; past that it highlights exactly as the
/// lexical highlighter does, and each new parse decides again.
@Suite
struct GrammarQualityGateTests {
    /// Swift code in a JSON document: all but the braces and a string lie under ERROR nodes.
    private static let mostlyErroneous = #"{"key": if let value = compute() { return value * 2 } else { return nil }}"#
    private static let clean = #"{"key": [1, 2, {"nested": true}]}"#

    @Test
    func `a document mostly under ERROR nodes is highlighted exactly as the lexical highlighter does`() async {
        #expect(await LanguageHighlighter.ensureArtifacts(for: "json"))
        let grammar = LanguageHighlighter.makeSession(language: "json")
        let lexical = LanguageHighlighter.makeSession(language: "json", preferGrammar: false)
        let source = Self.mostlyErroneous

        #expect(grammar.highlightDocument(source: source) == lexical.highlightDocument(source: source))
        #expect(
            grammar.highlightViewport(source: source, visibleLineRange: 0 ..< 1)
                == lexical.highlightViewport(source: source, visibleLineRange: 0 ..< 1))
        #expect(grammar.highlightDocumentTokens(source: source).isEmpty)
        #expect(!grammar.isGrammarBacked)
    }

    @Test
    func `a clean document is highlighted from its grammar`() async {
        #expect(await LanguageHighlighter.ensureArtifacts(for: "json"))
        let grammar = LanguageHighlighter.makeSession(language: "json")

        let tokens = grammar.highlightDocumentTokens(source: Self.clean)

        #expect(!tokens.isEmpty)
        #expect(grammar.isGrammarBacked)
    }

    @Test
    func `a document that crosses the threshold goes lexical and returns to its grammar once it heals`() async {
        #expect(await LanguageHighlighter.ensureArtifacts(for: "json"))
        let grammar = LanguageHighlighter.makeSession(language: "json")
        let lexical = LanguageHighlighter.makeSession(language: "json", preferGrammar: false)

        let before = grammar.highlightDocument(source: Self.clean)
        let backedBefore = grammar.isGrammarBacked
        let damaged = grammar.highlightDocument(source: Self.mostlyErroneous)
        let backedWhileDamaged = grammar.isGrammarBacked
        let healed = grammar.highlightDocument(source: Self.clean)

        #expect(backedBefore)
        #expect(!backedWhileDamaged)
        #expect(damaged == lexical.highlightDocument(source: Self.mostlyErroneous))
        #expect(grammar.isGrammarBacked)
        #expect(healed == before)
        #expect(healed != lexical.highlightDocument(source: Self.clean))
    }

    @Test(arguments: [(errorBytes: 4, passes: true), (errorBytes: 5, passes: false)])
    func `a parse passes the gate below five percent of its bytes under ERROR nodes`(errorBytes: Int, passes: Bool) {
        let error = SyntaxNode(type: "ERROR", byteRange: 10 ..< 10 + errorBytes, isError: true)
        let root = SyntaxNode(type: "document", children: [error], byteRange: 0 ..< 100)
        let tree = SyntaxTree(root: root, source: String(repeating: "x", count: 100))

        #expect(LanguageHighlighter.passesQualityGate(tree) == passes)
    }

    @Test
    func `a parse that did not reduce to the start rule does not pass the gate`() {
        let root = SyntaxNode(type: "_start", children: [SyntaxNode(type: "pair", byteRange: 0 ..< 4)])
        let tree = SyntaxTree(root: root, source: "a: b")

        #expect(!LanguageHighlighter.passesQualityGate(tree))
    }
}

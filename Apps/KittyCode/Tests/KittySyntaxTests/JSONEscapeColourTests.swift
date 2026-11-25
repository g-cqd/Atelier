import AtelierSyntaxModel
import Testing

@testable import KittySyntax

/// The JSON query lists `(string) @string` before `(escape_sequence) @escape`, so the string's token has the higher
/// priority; the merge must still let the narrower escape show through it.
struct JSONEscapeColourTests {
    @Test
    func `an escape sequence inside a json string keeps its colour through the merge`() async throws {
        #expect(await LanguageHighlighter.ensureArtifacts(for: "json"))
        let session = LanguageHighlighter.makeSession(language: "json")
        let source = #"{"a": "x\ny"}"#
        let tokens = session.highlightDocumentTokens(source: source)
        try #require(!tokens.isEmpty)

        let merged = HighlightMerger.merge(tokens, sourceByteCount: source.utf8.count)
        let roles = merged.map { ($0.byteRange, $0.role) }

        #expect(roles.contains { $0 == (8 ..< 10, .escape) })
        #expect(roles.contains { $0 == (6 ..< 8, .string) })
        #expect(roles.contains { $0 == (10 ..< 12, .string) })
        // The key reads as the property its earlier pattern names, not as the string a later one does.
        #expect(roles.contains { $0 == (1 ..< 4, .property) })
    }
}

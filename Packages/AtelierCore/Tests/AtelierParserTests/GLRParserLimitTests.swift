import Testing

@testable import AtelierParser

@Suite
struct GLRParserLimitTests {
    @Test
    func `A source past the token limit fails with that limit`() throws {
        let parser = try BundledGrammarFixture.parser(for: BundledGrammarFixture.json)
        // Openings only: no reduction runs, so the depth cap cannot stop the parse first.
        let source = String(repeating: "[", count: 100_001)

        #expect(throws: ParseError.tooManyTokens(limit: 100_000)) { try parser.parse(source) }
    }
}

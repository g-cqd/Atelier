import Testing

@testable import AtelierGrammar
@testable import AtelierParser

/// Reading tokens the stack cannot take, as merged lex modes and the error mode can offer them.
@Suite
struct UnviableTokenTests {
    /// Words, or strings whose text may start with a space.
    private static let wordsAndStrings = GrammarDefinition(
        name: "words_and_strings",
        rules: [
            ("source", .repeat(.choice([.symbol("word"), .symbol("string")]))),
            ("word", .pattern("[a-z]+")),
            ("string", .seq([.string("\""), .symbol("text"), .string("\"")])),
            ("text", .pattern(#"[^"]+"#))
        ],
        extras: [.pattern(#"\s"#)])

    @Test
    func `the error mode leaves out a token that starts as a separator does`() throws {
        let tree = try Self.parser(Self.wordsAndStrings).parse("a @ b c")

        #expect(tree.errorByteCount == 1)
        #expect(Self.count("word", in: tree.root) == 3)
    }

    /// How many nodes of type `type` the tree of `root` holds.
    private static func count(_ type: String, in root: SyntaxNode) -> Int {
        var count = 0
        var pending = [root]
        while let node = pending.popLast() {
            if node.type == type { count += 1 }
            pending.append(contentsOf: node.children)
        }
        return count
    }

    private static func parser(_ grammar: GrammarDefinition) throws -> GLRParser {
        let compiled = try ParseTableCompiler.compile(grammar)
        return GLRParser(
            parseTable: compiled.parseTable, lexTable: compiled.lexTable, productions: compiled.productions)
    }
}

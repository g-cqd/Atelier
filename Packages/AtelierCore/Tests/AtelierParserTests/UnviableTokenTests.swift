import Testing

@testable import AtelierGrammar
@testable import AtelierParser

/// Reading tokens the stack cannot take, as merged lex modes and the error mode can offer them.
@Suite
struct UnviableTokenTests {
    /// A word is followed by `)` in parentheses and by a string's text in a string: the state after the word stands
    /// for both, so its mode reads the text, which runs over ` ) ( b )` and wins. Swift's `line_str_text` did so after
    /// identifiers everywhere, one token running over the rest of the file. The unused `MARK` gives the grammar an
    /// external scanner, whose parse reads each stack's tokens on its own.
    private static let parenthesesOrStrings = GrammarDefinition(
        name: "shared_word",
        rules: [
            ("source", .repeat1(.symbol("_item"))),
            (
                "_item",
                .choice([
                    .seq([.string("("), .symbol("word"), .string(")")]),
                    .seq([.string("\""), .symbol("word"), .symbol("text"), .string("\"")]),
                    .symbol("MARK")
                ])
            ),
            ("word", .choice([.string("a"), .string("b")])),
            ("text", .pattern(#"[^"]+"#))
        ],
        extras: [.pattern(#"\s"#)],
        externals: [.symbol("MARK")])

    @Test
    func `a token only another context can take is read again as one the stack can take`() throws {
        let tree = try Self.parser(Self.parenthesesOrStrings).parse("( a ) ( b )", externalScanner: DecliningScanner())

        #expect(tree.errorByteCount == 0)
        #expect(Self.count("word", in: tree.root) == 2)
    }

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

/// A scanner that reads nothing.
private struct DecliningScanner: GrammarExternalScanner {
    static let externalNames = ["MARK"]

    mutating func scan(_ lexer: inout some ScannerLexer, validSymbols: [Bool]) -> Bool { false }

    func serialize(into buffer: inout [UInt8]) {}

    mutating func deserialize(_ state: ArraySlice<UInt8>) {}
}

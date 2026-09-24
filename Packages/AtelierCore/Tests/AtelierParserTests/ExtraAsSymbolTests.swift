import Testing

@testable import AtelierGrammar
@testable import AtelierParser

/// An extra that the grammar also uses in a rule is read as that symbol wherever the parse can take it, and skipped
/// elsewhere, as tree-sitter reads an extra as such only in a state with no other action for it. Swift's corpus case
/// “Class with modifiers” separates two class members with a block comment alone, which its grammar allows.
@Suite
struct ExtraAsSymbolTests {
    /// Items separated by `;` or by a comment, which may also come anywhere as an extra.
    private static let grammar = GrammarDefinition(
        name: "comment_separators",
        rules: [
            ("source", .seq([.symbol("item"), .repeat(.seq([.symbol("_separator"), .symbol("item")]))])),
            ("_separator", .choice([.string(";"), .symbol("comment")])),
            ("item", .choice([.string("x"), .string("y")]))
        ],
        extras: [.pattern(#"\s"#), .symbol("comment")],
        externals: [.symbol("comment")])

    @Test
    func `an extra the parse can take as a symbol separates two items`() throws {
        let tree = try Self.parser().parse("x /*c*/ y", externalScanner: BlockCommentScanner())

        #expect(tree.errorByteCount == 0)
        #expect(Self.leaves(of: tree.root) == ["\"x\"", "comment", "\"y\""])
    }

    @Test
    func `an extra the parse cannot take as a symbol stays an extra`() throws {
        let tree = try Self.parser().parse("x; /*c*/ y", externalScanner: BlockCommentScanner())

        #expect(tree.errorByteCount == 0)
        #expect(Self.leaves(of: tree.root) == ["\"x\"", "\";\"", "\"y\""])
        #expect(tree.root.children.filter(\.isExtra).map(\.type) == ["comment"])
    }

    private static func parser() throws -> GLRParser {
        let compiled = try ParseTableCompiler.compile(grammar)
        return GLRParser(
            parseTable: compiled.parseTable, lexTable: compiled.lexTable, productions: compiled.productions)
    }

    /// The types of the tree's tokens in order, extras and empty reductions left out.
    private static func leaves(of root: SyntaxNode) -> [String] {
        var leaves: [String] = []
        var pending = [root]
        while let node = pending.popLast() {
            guard !node.isExtra else { continue }
            if node.children.isEmpty {
                if !node.byteRange.isEmpty { leaves.append(node.type) }
            } else {
                pending.append(contentsOf: node.children.reversed())
            }
        }
        return leaves
    }
}

/// Reads `/*…*/` as `comment`, which the grammar lists among its extras.
private struct BlockCommentScanner: GrammarExternalScanner {
    static let externalNames = ["comment"]

    mutating func scan(_ lexer: inout some ScannerLexer, validSymbols: [Bool]) -> Bool {
        while lexer.lookahead == UInt32(UInt8(ascii: " ")) { lexer.advance(skip: true) }
        guard validSymbols[0], lexer.lookahead == UInt32(UInt8(ascii: "/")) else { return false }
        lexer.advance(skip: false)
        guard lexer.lookahead == UInt32(UInt8(ascii: "*")) else { return false }
        while !lexer.isAtEnd {
            lexer.advance(skip: false)
            if lexer.lookahead == UInt32(UInt8(ascii: "/")) {
                lexer.advance(skip: false)
                lexer.resultSymbol = 0
                return true
            }
        }
        return false
    }

    func serialize(into buffer: inout [UInt8]) {}

    mutating func deserialize(_ state: ArraySlice<UInt8>) {}
}

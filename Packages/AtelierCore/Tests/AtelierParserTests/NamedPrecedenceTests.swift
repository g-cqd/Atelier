import Testing

@testable import AtelierGrammar
@testable import AtelierParser

/// A grammar's `precedences` lists order named precedences and rules, earlier over later, as tree-sitter orders them.
/// JavaScript names every operator's precedence; read as 0, `i + j * 3` grouped as `(i + j) * 3` and `{}` became an
/// object, and a quarter of JavaScript's corpus cases parsed into other trees.
@Suite
struct NamedPrecedenceTests {
    @Test
    func `an operator whose named precedence comes first binds tighter`() throws {
        let binary = { (spelling: String, precedence: String) -> Rule in
            .precLeft(.name(precedence), .seq([.symbol("_expression"), .string(spelling), .symbol("_expression")]))
        }
        let grammar = GrammarDefinition(
            name: "named_operators",
            rules: [
                ("program", .symbol("_expression")),
                ("_expression", .choice([.symbol("binary"), .symbol("identifier")])),
                ("binary", .choice([binary("+", "plus"), binary("*", "times")])),
                ("identifier", .pattern("[a-z]+"))
            ],
            extras: [.pattern(#"\s"#)],
            precedences: [[.literal("times"), .literal("plus")]])

        let tree = try Self.parser(grammar).parse("i + j * k")

        #expect(Self.sexp(tree.root) == "(program (binary (identifier) (binary (identifier) (identifier))))")
    }

    @Test
    func `a precedence list orders a rule it names against a named precedence`() throws {
        let grammar = GrammarDefinition(
            name: "block_or_object",
            rules: [
                ("program", .repeat(.symbol("_statement"))),
                ("_statement", .choice([.symbol("statement_block"), .symbol("expression_statement")])),
                // Declared first, the object would win a tie between the two readings.
                ("expression_statement", .seq([.symbol("object"), .optional(.string(";"))])),
                ("object", .prec(.name("object"), .seq([.string("{"), .string("}")]))),
                ("statement_block", .precRight(0, .seq([.string("{"), .string("}")])))
            ],
            extras: [.pattern(#"\s"#)],
            precedences: [[.symbol("statement_block"), .literal("object")]])

        let tree = try Self.parser(grammar).parse("{}")

        #expect(Self.sexp(tree.root) == "(program (statement_block))")
    }

    private static func parser(_ grammar: GrammarDefinition) throws -> GLRParser {
        let compiled = try ParseTableCompiler.compile(grammar)
        return GLRParser(
            parseTable: compiled.parseTable, lexTable: compiled.lexTable, productions: compiled.productions)
    }

    /// The tree's named, visible nodes as an S-expression.
    private static func sexp(_ node: SyntaxNode) -> String {
        let children = node.children.map(sexp).filter { !$0.isEmpty }
        guard node.isNamed, !node.type.hasPrefix("_") else { return children.joined(separator: " ") }
        return "(" + ([node.type] + children).joined(separator: " ") + ")"
    }
}

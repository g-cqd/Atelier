import Testing

@testable import AtelierGrammar
@testable import AtelierParser

@Suite
struct CoreMergingIntegrationTests {
    @Test(arguments: ["axc", "axd", "bxc", "bxd"])
    func `merging a core preserves each contextual reduction`(source: String) throws {
        let grammar = GrammarDefinition(
            name: "non_lalr",
            rules: [
                (
                    "s",
                    .choice([
                        .seq([.string("a"), .symbol("E"), .string("c")]),
                        .seq([.string("a"), .symbol("F"), .string("d")]),
                        .seq([.string("b"), .symbol("F"), .string("c")]),
                        .seq([.string("b"), .symbol("E"), .string("d")])
                    ])
                ),
                ("E", .prec(1, .string("x"))),
                ("F", .string("x"))
            ],
            extras: [])
        let compiled = try ParseTableCompiler.compile(grammar)
        let parser = GLRParser(
            parseTable: compiled.parseTable, lexTable: compiled.lexTable, productions: compiled.productions)

        let tree = try parser.parse(source)

        #expect(!tree.root.containsError)
        #expect(tree.root.byteRange == 0 ..< source.utf8.count)
    }
}

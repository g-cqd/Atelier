import Testing

@testable import AtelierGrammar
@testable import AtelierParser

/// Of two parses that tie on errors and dynamic precedence, tree-sitter keeps the tree whose symbols come first in
/// the grammar's order. Swift's `something.foo()` reads `something.foo` both as a navigation from an expression and as
/// a nested type, a declared conflict; tree-sitter keeps the navigation, `_expression` being declared before
/// `_navigable_type_expression`, and thirty of Swift's corpus cases expect it.
@Suite
struct AmbiguityOrderTests {
    @Test(arguments: [["navigation", "type"], ["type", "navigation"]])
    func `an ambiguous parse keeps the reading whose rule the grammar declares first`(order: [String]) throws {
        let readings: [String: Rule] = [
            "navigation": .seq([.symbol("_expression"), .string("."), .symbol("name")]),
            "type": .seq([.symbol("name"), .repeat(.seq([.string("."), .symbol("name")]))])
        ]
        let grammar = GrammarDefinition(
            name: "ambiguous_target",
            rules: [
                ("source", .seq([.symbol("target"), .string("!")])),
                ("target", .choice([.symbol("navigation"), .symbol("type")]))
            ] + order.compactMap { name in readings[name].map { (name, $0) } } + [
                ("_expression", .symbol("name")), ("name", .pattern("[a-z]+"))
            ],
            extras: [.pattern(#"\s"#)],
            conflicts: [["_expression", "type"]])
        let compiled = try ParseTableCompiler.compile(grammar)
        let parser = GLRParser(
            parseTable: compiled.parseTable, lexTable: compiled.lexTable, productions: compiled.productions)

        let tree = try parser.parse("a.b!")

        #expect(tree.errorByteCount == 0)
        #expect(tree.root.children.first?.children.first?.type == order[0])
    }
}

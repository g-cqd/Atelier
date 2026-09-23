import Foundation
import Testing

@testable import AtelierGrammar
@testable import AtelierParser

/// Ambiguities only `prec.dynamic` settles: two readings of the same text that parse without errors.
@Suite
struct GLRParserDynamicPrecedenceTests {
    @Test(arguments: [(first: 0, second: 1), (first: -1, second: 0)])
    func `Of two error-free parses, the one of higher dynamic precedence wins`(first: Int, second: Int) throws {
        let compiled = try ParseTableCompiler.compile(GrammarLoader.parse(Data(Self.grammar(first, second).utf8)))
        let parser = GLRParser(
            parseTable: compiled.parseTable, lexTable: compiled.lexTable, productions: compiled.productions)

        let tree = try parser.parse("x")

        #expect(tree.root.type == "s")
        #expect(tree.root.children.map(\.type) == ["second"])
    }

    /// `s: first | second`, where both read the one token `x`, with dynamic precedences `first` and `second`. The
    /// compiler lists `first`'s reduction before `second`'s, so without dynamic precedence the parse keeps `first`.
    private static func grammar(_ first: Int, _ second: Int) -> String {
        """
        {
            "name": "ambiguous",
            "rules": {
                "s": {
                    "type": "CHOICE",
                    "members": [{"type": "SYMBOL", "name": "first"}, {"type": "SYMBOL", "name": "second"}]
                },
                "first": {"type": "PREC_DYNAMIC", "value": \(first), "content": {"type": "STRING", "value": "x"}},
                "second": {"type": "PREC_DYNAMIC", "value": \(second), "content": {"type": "STRING", "value": "x"}}
            }
        }
        """
    }
}

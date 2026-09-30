import Foundation
import Testing

@testable import AtelierGrammar
@testable import AtelierParser

/// Operators whose grouping only precedence and associativity decide, as tree-sitter grammars write them.
@Suite
struct GLRParserPrecedenceTests {
    @Test
    func `A higher-precedence operator on the right binds tighter`() throws {
        #expect(try Self.grouping(of: "a + b * c") == "(a + (b * c))")
    }

    @Test
    func `A higher-precedence operator on the left binds tighter`() throws {
        #expect(try Self.grouping(of: "a * b + c") == "((a * b) + c)")
    }

    @Test
    func `A left-associative operator groups to the left`() throws {
        #expect(try Self.grouping(of: "a + b + c") == "((a + b) + c)")
    }

    @Test
    func `A right-associative operator groups to the right`() throws {
        #expect(try Self.grouping(of: "a ^ b ^ c") == "(a ^ (b ^ c))")
    }

    @Test
    func `Precedence and associativity leave the parser no conflict to fork on`() throws {
        let table = try ParseTableCompiler.compile(ArithmeticGrammar.definition()).parseTable

        let conflicts = table.actions.rows.joined()
            .filter { action in
                if case .conflict = action { true } else { false }
            }

        #expect(conflicts.isEmpty)
    }

    /// The source with every operator's operands in parentheses, as the parser grouped them.
    private static func grouping(of source: String) throws -> String {
        let compiled = try ParseTableCompiler.compile(ArithmeticGrammar.definition())
        let parser = GLRParser(
            parseTable: compiled.parseTable, lexTable: compiled.lexTable, productions: compiled.productions)
        let tree = try parser.parse(source)
        #expect(!tree.root.containsError)
        return try rendered(tree.root, source: source)
    }

    private static func rendered(_ node: SyntaxNode, source: String) throws -> String {
        switch node.type {
            case "sum", "product", "power":
                let left = try #require(node.child(forField: "left"))
                let right = try #require(node.child(forField: "right"))
                let symbol = try #require(node.children.first { !$0.isNamed })
                return "(\(try rendered(left, source: source)) \(symbol.text(from: source)) "
                    + "\(try rendered(right, source: source)))"
            case "expression":
                return try rendered(try #require(node.children.first), source: source)
            default:
                return node.text(from: source)
        }
    }
}

/// `expression: sum | product | power | operand`, with `+` left-associative at precedence 1, `*` left-associative at
/// 2 and `^` right-associative at 3: every operator conflicts with every other until precedence resolves it.
enum ArithmeticGrammar {
    static func definition() throws -> GrammarDefinition {
        try GrammarLoader.parse(Data(json.utf8))
    }

    private static func binary(_ kind: String, _ precedence: Int, _ symbol: String) -> String {
        """
        {
            "type": "\(kind)",
            "value": \(precedence),
            "content": {
                "type": "SEQ",
                "members": [
                    {"type": "FIELD", "name": "left", "content": {"type": "SYMBOL", "name": "expression"}},
                    {"type": "STRING", "value": "\(symbol)"},
                    {"type": "FIELD", "name": "right", "content": {"type": "SYMBOL", "name": "expression"}}
                ]
            }
        }
        """
    }

    private static let json = """
        {
            "name": "arithmetic",
            "rules": {
                "expression": {
                    "type": "CHOICE",
                    "members": [
                        {"type": "SYMBOL", "name": "sum"},
                        {"type": "SYMBOL", "name": "product"},
                        {"type": "SYMBOL", "name": "power"},
                        {"type": "SYMBOL", "name": "operand"}
                    ]
                },
                "sum": \(binary("PREC_LEFT", 1, "+")),
                "product": \(binary("PREC_LEFT", 2, "*")),
                "power": \(binary("PREC_RIGHT", 3, "^")),
                "operand": {
                    "type": "CHOICE",
                    "members": [
                        {"type": "STRING", "value": "a"},
                        {"type": "STRING", "value": "b"},
                        {"type": "STRING", "value": "c"}
                    ]
                }
            }
        }
        """
}

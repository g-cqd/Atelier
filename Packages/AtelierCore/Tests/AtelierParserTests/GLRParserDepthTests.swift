import Foundation
import Testing

@testable import AtelierGrammar
@testable import AtelierParser

@Suite
struct GLRParserDepthTests {
    @Test
    func `JSON nested past the depth cap declines on a pool-sized stack`() async throws {
        // 9,000 nested arrays make a tree about 18,000 levels deep; the parse holds most of it when it declines.
        let parser = try BundledGrammarFixture.parser(for: BundledGrammarFixture.json)
        let source = String(repeating: "[", count: 9_000) + String(repeating: "]", count: 9_000)

        let error = await onThread { Self.parseError(parser, source) }

        #expect(error == GLRParser.treeTooDeep)
    }

    @Test(arguments: [(16_381, false), (16_382, true)])
    func `The node an unfinished parse adds above its stack counts toward the depth cap`(
        repetitions: Int,
        declines: Bool
    ) async throws {
        // Without `tail`, the parse ends holding `item`, n + 2 levels tall, and `end`, under one more level.
        let json = """
            {
                "name": "unfinished",
                "rules": {
                    "s": {
                        "type": "SEQ",
                        "members": [
                            {"type": "SYMBOL", "name": "item"},
                            {"type": "STRING", "value": "end"},
                            {"type": "STRING", "value": "tail"}
                        ]
                    },
                    "item": {"type": "REPEAT1", "content": {"type": "STRING", "value": "x"}}
                }
            }
            """
        let compiled = try ParseTableCompiler.compile(GrammarLoader.parse(Data(json.utf8)))
        let parser = GLRParser(
            parseTable: compiled.parseTable, lexTable: compiled.lexTable, productions: compiled.productions)
        let source = String(repeating: "x", count: repetitions) + "end"

        let error = await onThread { Self.parseError(parser, source) }

        #expect(error == (declines ? GLRParser.treeTooDeep : nil))
    }

    @Test
    func `A fork merged away frees its deep subtree on a pool-sized stack`() async throws {
        // `left` and `right` both repeat `x`, so the parse forks at the first `x` and each fork builds its own chain
        // of 5,000 nodes. The forks reach the same state history before `end` and merge, dropping one chain.
        let parser = try Self.twinsParser(endingWith: "end")
        let source = String(repeating: "x", count: 5_000) + "end"

        let rootType = await onThread { Self.rootType(parser, source) }

        #expect(rootType == "s")
    }

    @Test
    func `A fork left over at the end of the input frees its deep subtree on a pool-sized stack`() async throws {
        // Both forks accept, each with its own chain of 5,000 nodes; the parse keeps one and drops the other.
        let parser = try Self.twinsParser(endingWith: nil)
        let source = String(repeating: "x", count: 5_000)

        let rootType = await onThread { Self.rootType(parser, source) }

        #expect(rootType == "s")
    }

    /// A parser for `s: item terminator?`, `item: left | right`, where `left` and `right` both repeat the token `x`,
    /// so a parse forks at the first `x`.
    private static func twinsParser(endingWith terminator: String?) throws -> GLRParser {
        let start: String
        if let terminator {
            start = """
                {
                    "type": "SEQ",
                    "members": [{"type": "SYMBOL", "name": "item"}, {"type": "STRING", "value": "\(terminator)"}]
                }
                """
        } else {
            start = #"{"type": "SYMBOL", "name": "item"}"#
        }
        let json = """
            {
                "name": "twins",
                "rules": {
                    "s": \(start),
                    "item": {
                        "type": "CHOICE",
                        "members": [{"type": "SYMBOL", "name": "left"}, {"type": "SYMBOL", "name": "right"}]
                    },
                    "left": {"type": "REPEAT1", "content": {"type": "STRING", "value": "x"}},
                    "right": {"type": "REPEAT1", "content": {"type": "STRING", "value": "x"}}
                }
            }
            """
        let compiled = try ParseTableCompiler.compile(GrammarLoader.parse(Data(json.utf8)))
        return GLRParser(
            parseTable: compiled.parseTable, lexTable: compiled.lexTable, productions: compiled.productions)
    }

    private static func parseError(_ parser: GLRParser, _ source: String) -> ParseError? {
        do {
            _ = try parser.parse(source)
            return nil
        } catch {
            return error
        }
    }

    /// The root's type. In a release build the tree dies at its last use, before the copy of the root read from it:
    /// the copy is then the last holder of the 5,000-level chain, and frees it.
    private static func rootType(_ parser: GLRParser, _ source: String) -> String? {
        guard let tree = try? parser.parse(source) else { return nil }
        return tree.root.type
    }
}

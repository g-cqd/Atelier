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

    /// The root's type, read while the tree is alive: a copy of a deep node that outlives its tree is freed
    /// recursively.
    private static func rootType(_ parser: GLRParser, _ source: String) -> String? {
        guard let tree = try? parser.parse(source) else { return nil }
        return tree.root.type
    }
}

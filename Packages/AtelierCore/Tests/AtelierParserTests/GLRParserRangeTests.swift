import Foundation
import Testing

@testable import AtelierGrammar
@testable import AtelierParser

@Suite
struct GLRParserRangeTests {
    @Test
    func `An empty reduction after a token sits at that token's end`() throws {
        // `s` ends with `e`, which is empty: placed at offset 0, it would end `s` before `a` starts.
        let json = """
            {
                "name": "trailing_empty",
                "rules": {
                    "s": {"type": "SEQ", "members": [{"type": "STRING", "value": "a"}, {"type": "SYMBOL", "name": "e"}]},
                    "e": {"type": "BLANK"}
                }
            }
            """
        let compiled = try ParseTableCompiler.compile(GrammarLoader.parse(Data(json.utf8)))
        let parser = GLRParser(
            parseTable: compiled.parseTable, lexTable: compiled.lexTable, productions: compiled.productions)

        let tree = try parser.parse(" a")

        #expect(tree.root.type == "s")
        #expect(tree.root.byteRange == 1 ..< 2)
        #expect(tree.root.children.map(\.byteRange) == [1 ..< 2, 2 ..< 2])
        #expect(tree.root.children.last?.pointRange == Point(row: 0, column: 2) ..< Point(row: 0, column: 2))
    }

    @Test(arguments: ["[[]]", "[{},{}]", "{\"\": [true, {}]}", " [ [ ] ]\n"])
    func `Every node of a JSON tree lies within its parent, after its left sibling`(source: String) throws {
        let parser = try BundledGrammarFixture.parser(for: BundledGrammarFixture.json)

        let tree = try parser.parse(source)

        #expect(tree.root.type == "document")
        #expect(tree.root.rangesNestInSourceOrder)
    }

    @Test(arguments: ["a /* x */ {", "/**/ a {"])
    func `CSS that used to trap or loop parses into nested ranges`(source: String) throws {
        let parser = try BundledGrammarFixture.parser(for: BundledGrammarFixture.css)

        let tree = try parser.parse(source)

        #expect(tree.root.rangesNestInSourceOrder)
    }
}

extension SyntaxNode {
    /// Whether every node below this one lies within its parent's byte and point ranges, after its left sibling's.
    fileprivate var rangesNestInSourceOrder: Bool {
        var pending = [self]
        while let node = pending.popLast() {
            var previous: SyntaxNode?
            for child in node.children {
                guard node.byteRange.lowerBound <= child.byteRange.lowerBound,
                    child.byteRange.upperBound <= node.byteRange.upperBound,
                    node.pointRange.lowerBound <= child.pointRange.lowerBound,
                    child.pointRange.upperBound <= node.pointRange.upperBound,
                    (previous?.byteRange.upperBound ?? child.byteRange.lowerBound) <= child.byteRange.lowerBound
                else { return false }
                previous = child
            }
            pending.append(contentsOf: node.children)
        }
        return true
    }
}

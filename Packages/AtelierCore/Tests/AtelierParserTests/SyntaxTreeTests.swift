import Foundation
import Testing

@testable import AtelierGrammar
@testable import AtelierParser

@Suite
struct SyntaxTreeTests {
    @Test
    func `Walk visits all nodes`() {
        let leaf = SyntaxNode(type: "leaf", byteRange: 0 ..< 3)
        let root = SyntaxNode(type: "root", children: [leaf], byteRange: 0 ..< 3)
        let tree = SyntaxTree(root: root, source: "abc")

        var visited: [String] = []
        tree.walk { node, _ in
            visited.append(node.type)
            return true
        }
        #expect(visited == ["root", "leaf"])
    }

    @Test
    func `A tree built by hand counts each byte under its outermost error nodes once`() {
        let inner = SyntaxNode(type: "ERROR", byteRange: 3 ..< 5, isError: true)
        let outer = SyntaxNode(type: "ERROR", children: [inner], byteRange: 2 ..< 6, isError: true)
        let overlapping = SyntaxNode(type: "ERROR", byteRange: 5 ..< 9, isError: true)
        let clean = SyntaxNode(type: "word", byteRange: 10 ..< 14)
        let root = SyntaxNode(type: "root", children: [outer, overlapping, clean], byteRange: 0 ..< 20)

        let tree = SyntaxTree(root: root, source: String(repeating: "x", count: 20))

        #expect(tree.errorByteCount == 7)
    }

    @Test
    func `A parse counts the bytes of the tokens it could not take`() throws {
        let grammar = GrammarDefinition(
            name: "words",
            rules: [("source", .repeat1(.symbol("word"))), ("word", .pattern("[a-z]+"))],
            extras: [.pattern(#"\s"#)])
        let compiled = try ParseTableCompiler.compile(grammar)
        let parser = GLRParser(
            parseTable: compiled.parseTable, lexTable: compiled.lexTable, productions: compiled.productions)

        let tree = try parser.parse("ab 12")

        #expect(tree.errorByteCount == 2)
    }

    @Test
    func `Node at byte offset`() {
        let child1 = SyntaxNode(type: "a", byteRange: 0 ..< 3)
        let child2 = SyntaxNode(type: "b", byteRange: 3 ..< 6)
        let root = SyntaxNode(type: "root", children: [child1, child2], byteRange: 0 ..< 6)
        let tree = SyntaxTree(root: root, source: "abcdef")

        let found = tree.nodeAt(byteOffset: 4)
        #expect(found?.type == "b")
    }

    @Test
    func `A tree too deep to free recursively releases on a pool-sized stack`() async {
        // Freed recursively, a chain overflows a 512 KiB stack between 2,000 and 3,000 levels.
        let rootChildren = await onThread {
            let tree = Self.makeChain(depth: 100_000)
            return tree.root.children.count
        }
        #expect(rootChildren == 1)
    }

    @Test
    func `A tree whose fields repeat its children releases each subtree once`() async {
        // The parser stores a field as a copy of a child; walking fields and children alike would reach the leaf of
        // this chain 2^63 times.
        let rootFields = await onThread {
            let tree = Self.makeChain(depth: 64, fieldPerLevel: true)
            return tree.root.fields.count
        }
        #expect(rootFields == 1)
    }

    @Test
    func `Releasing a tree leaves a subtree held elsewhere whole`() {
        var subtree: SyntaxNode?
        do {
            let tree = Self.makeChain(depth: 10, fieldPerLevel: true)
            subtree = tree.root.children.first
        }
        var depth = 0
        var node = subtree
        while let current = node {
            depth += 1
            node = current.children.first
        }
        #expect(depth == 9)
        #expect(subtree?.fields["inner"]?.first?.children.count == 1)
    }

    /// A `depth`-level tree whose root chains down through `children[0]` to a single leaf; with `fieldPerLevel`, each
    /// branch also names its child in an `inner` field, as the parser records fields.
    private static func makeChain(depth: Int, fieldPerLevel: Bool = false) -> SyntaxTree {
        var node = SyntaxNode(type: "leaf", byteRange: 0 ..< 1)
        for _ in 1 ..< depth {
            node = SyntaxNode(
                type: "branch", children: [node], byteRange: 0 ..< 1, fields: fieldPerLevel ? ["inner": [node]] : [:])
        }
        return SyntaxTree(root: node, source: "x")
    }
}

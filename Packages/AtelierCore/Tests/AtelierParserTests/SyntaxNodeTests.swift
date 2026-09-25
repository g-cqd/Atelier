import Foundation
import Testing

@testable import AtelierGrammar
@testable import AtelierParser

@Suite
struct SyntaxNodeTests {
    @Test
    func `Node text extraction`() {
        let source = "hello world"
        let node = SyntaxNode(type: "word", byteRange: 0 ..< 5)
        #expect(node.text(from: source) == "hello")
    }

    @Test
    func `Node text extraction returns empty string for out-of-bounds lower bound`() {
        let source = "hello"
        let node = SyntaxNode(type: "word", byteRange: 20 ..< 25)
        #expect(node.text(from: source).isEmpty)
    }

    @Test
    func `Named children filter`() {
        let child1 = SyntaxNode(type: "name", isNamed: true)
        let child2 = SyntaxNode(type: ",", isNamed: false)
        let parent = SyntaxNode(type: "list", children: [child1, child2])
        #expect(parent.namedChildren.count == 1)
        #expect(parent.namedChildren[0].type == "name")
    }

    @Test
    func `Changing a copy's children and fields leaves the original's alone`() {
        let leaf = SyntaxNode(type: "leaf")
        let original = SyntaxNode(type: "pair", children: [leaf], fields: ["key": [leaf]])
        var copy = original

        copy.children.append(SyntaxNode(type: "extra"))
        copy.fields["value"] = [leaf]

        #expect(original.children.map(\.type) == ["leaf"])
        #expect(original.fields.keys.sorted() == ["key"])
        #expect(copy.children.map(\.type) == ["leaf", "extra"])
        #expect(copy.fields.keys.sorted() == ["key", "value"])
    }

    @Test
    func `A chain of nodes too deep to free recursively frees on a pool-sized stack`() async {
        // Freed recursively, a chain overflows a 512 KiB stack between 2,000 and 3,000 levels in a release build, and
        // sooner in a debug one; no tree holds this one to free it.
        let rootChildren = await onThread {
            let root = Self.makeChain(depth: 100_000) { SyntaxNode(type: "branch", children: [$0]) }
            return root.children.count
        }
        #expect(rootChildren == 1)
    }

    @Test
    func `A chain of nodes linked only by fields frees on a pool-sized stack`() async {
        let rootFields = await onThread {
            let root = Self.makeChain(depth: 100_000) { SyntaxNode(type: "branch", fields: ["inner": [$0]]) }
            return root.fields.count
        }
        #expect(rootFields == 1)
    }

    /// A `depth`-level chain from a leaf up, each level made by `wrap` from the one below.
    private static func makeChain(depth: Int, wrap: (SyntaxNode) -> SyntaxNode) -> SyntaxNode {
        var node = SyntaxNode(type: "leaf")
        for _ in 1 ..< depth { node = wrap(node) }
        return node
    }
}

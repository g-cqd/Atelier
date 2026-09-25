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

    @Test(arguments: [false, true])
    func `Two chains too deep to compare recursively compare on a pool-sized stack`(linkedByFields: Bool) async {
        // Compared recursively, two chains overflow a 512 KiB stack a few thousand levels down. Built apart, the two
        // share no storage, so the comparison walks every level.
        let (same, different) = await onThread {
            let wrap: (SyntaxNode) -> SyntaxNode = { inner in
                linkedByFields
                    ? SyntaxNode(type: "branch", fields: ["inner": [inner]])
                    : SyntaxNode(type: "branch", children: [inner])
            }
            let chain = Self.makeChain(depth: 100_000, wrap: wrap)
            let twin = Self.makeChain(depth: 100_000, wrap: wrap)
            let other = Self.makeChain(depth: 100_000, leafType: "other", wrap: wrap)
            return (chain == twin, chain == other)
        }
        #expect(same)
        #expect(!different)
    }

    @Test(.timeLimit(.minutes(1)))
    func `Two trees whose fields repeat their children compare each subtree once`() {
        // The parser stores a field as a copy of a child; comparing fields and children alike would compare the
        // leaves of these chains 2^63 times.
        let wrap: (SyntaxNode) -> SyntaxNode = { SyntaxNode(type: "branch", children: [$0], fields: ["inner": [$0]]) }
        let chain = Self.makeChain(depth: 64, wrap: wrap)
        let twin = Self.makeChain(depth: 64, wrap: wrap)
        let other = Self.makeChain(depth: 64, leafType: "other", wrap: wrap)

        #expect(chain == twin)
        #expect(chain != other)
    }

    @Test
    func `Nodes differ by any child, field name or field node`() {
        let (a, b) = (SyntaxNode(type: "a"), SyntaxNode(type: "b"))
        let node = SyntaxNode(type: "pair", children: [a, b], fields: ["key": [a]])

        #expect(node == SyntaxNode(type: "pair", children: [a, b], fields: ["key": [a]]))
        #expect(node != SyntaxNode(type: "pair", children: [a], fields: ["key": [a]]))
        #expect(node != SyntaxNode(type: "pair", children: [b, a], fields: ["key": [a]]))
        #expect(node != SyntaxNode(type: "pair", children: [a, b], fields: ["value": [a]]))
        #expect(node != SyntaxNode(type: "pair", children: [a, b], fields: ["key": [b]]))
        #expect(node != SyntaxNode(type: "pair", children: [a, b], fields: ["key": [a, a]]))
        #expect(node != SyntaxNode(type: "pair", children: [a, b]))
        var emptied = SyntaxNode(type: "leaf", children: [a])
        emptied.children = []
        #expect(emptied == SyntaxNode(type: "leaf"))
    }

    @Test(arguments: [false, true])
    func `A chain grown one level at a time through its nodes' children or fields frees on a pool-sized stack`(
        throughFields: Bool
    ) async {
        // A node keeps a small subtree without fields inline, freed recursively; each level added here must move the
        // chain out of line once it is too tall, or dropping it recurses 100,000 levels.
        let depth = await onThread {
            let root = Self.makeChain(depth: 100_000) { inner in
                var node = SyntaxNode(type: "branch")
                if throughFields { node.fields["inner"] = [inner] } else { node.children.append(inner) }
                return node
            }
            var depth = 1
            var node = root
            while let inner = throughFields ? node.fields["inner"]?.first : node.children.first {
                depth += 1
                node = inner
            }
            return depth
        }
        #expect(depth == 100_000)
    }

    @Test
    func `Nodes with the same children and fields are equal however they came by them`() {
        let leaf = SyntaxNode(type: "leaf")
        var emptiedFields = SyntaxNode(type: "pair", children: [leaf], fields: ["key": [leaf]])
        emptiedFields.fields = [:]
        var grown = SyntaxNode(type: "pair")
        grown.children.append(leaf)

        #expect(emptiedFields == SyntaxNode(type: "pair", children: [leaf]))
        #expect(grown == SyntaxNode(type: "pair", children: [leaf]))
        #expect(grown == emptiedFields)
    }

    /// A `depth`-level chain from a leaf of type `leafType` up, each level made by `wrap` from the one below.
    private static func makeChain(
        depth: Int, leafType: String = "leaf", wrap: (SyntaxNode) -> SyntaxNode
    ) -> SyntaxNode {
        var node = SyntaxNode(type: leafType)
        for _ in 1 ..< depth { node = wrap(node) }
        return node
    }
}

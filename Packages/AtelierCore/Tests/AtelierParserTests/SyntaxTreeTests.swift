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
    func `Node at byte offset`() {
        let child1 = SyntaxNode(type: "a", byteRange: 0 ..< 3)
        let child2 = SyntaxNode(type: "b", byteRange: 3 ..< 6)
        let root = SyntaxNode(type: "root", children: [child1, child2], byteRange: 0 ..< 6)
        let tree = SyntaxTree(root: root, source: "abcdef")

        let found = tree.nodeAt(byteOffset: 4)
        #expect(found?.type == "b")
    }

    @Test
    func `deeply nested tree deinit drains without stack overflow`() {
        // Deep enough to exercise the iterative deinit; building the chain copies O(depth²) nodes, so going deeper
        // only slows the test.
        let tree = Self.makeDeepTree(depth: 1_000)
        _ = tree
        #expect(
            Bool(true),
            "got here = iterative deinit unwound the chain without crashing")
    }

    /// Constructs a `depth`-deep `SyntaxTree` whose root chains down
    /// through `children[0]` to a single leaf at the bottom.
    private static func makeDeepTree(depth: Int) -> SyntaxTree {
        var node = SyntaxNode(type: "leaf", byteRange: 0 ..< 1)
        for level in 1 ... depth {
            node = SyntaxNode(type: "branch-\(level)", children: [node], byteRange: 0 ..< 1)
        }
        return SyntaxTree(root: node, source: "x")
    }
}

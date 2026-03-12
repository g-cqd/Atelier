import Foundation
import Testing

@testable import KittyGrammar
@testable import KittyParser

@Suite
struct SyntaxTreeTests {
    @Test
    func `Walk visits all nodes`() {
        let leaf = SyntaxNode(type: "leaf", byteRange: 0..<3)
        let root = SyntaxNode(type: "root", children: [leaf], byteRange: 0..<3)
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
        let child1 = SyntaxNode(type: "a", byteRange: 0..<3)
        let child2 = SyntaxNode(type: "b", byteRange: 3..<6)
        let root = SyntaxNode(type: "root", children: [child1, child2], byteRange: 0..<6)
        let tree = SyntaxTree(root: root, source: "abcdef")

        let found = tree.nodeAt(byteOffset: 4)
        #expect(found?.type == "b")
    }
}

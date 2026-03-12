import Foundation
import Testing

@testable import KittyGrammar
@testable import KittyParser

@Suite
struct SyntaxNodeTests {
    @Test
    func `Node text extraction`() {
        let source = "hello world"
        let node = SyntaxNode(type: "word", byteRange: 0..<5)
        #expect(node.text(from: source) == "hello")
    }

    @Test
    func `Node text extraction returns empty string for out-of-bounds lower bound`() {
        let source = "hello"
        let node = SyntaxNode(type: "word", byteRange: 20..<25)
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
}

import Foundation
import Testing

@testable import KittyGrammar
@testable import KittyParser

@Suite
struct TextEditTests {
    @Test
    func `Apply edit shifts byte ranges`() {
        let child1 = SyntaxNode(type: "a", byteRange: 0 ..< 3)
        let child2 = SyntaxNode(type: "b", byteRange: 3 ..< 6)
        let root = SyntaxNode(type: "root", children: [child1, child2], byteRange: 0 ..< 6)
        let tree = SyntaxTree(root: root, source: "abcdef")

        // Insert 2 bytes at position 3
        let edit = TextEdit(startByte: 3, oldEndByte: 3, newEndByte: 5)
        let edited = tree.applying(edit: edit)

        // child2 should have shifted by 2
        #expect(edited.root.children[1].byteRange.lowerBound == 5)
    }

    @Test
    func `Apply edit shifts point ranges and field nodes`() {
        let left = SyntaxNode(
            type: "left",
            byteRange: 0 ..< 3,
            pointRange: Point(row: 0, column: 0) ..< Point(row: 0, column: 3)
        )
        let right = SyntaxNode(
            type: "right",
            byteRange: 3 ..< 6,
            pointRange: Point(row: 0, column: 3) ..< Point(row: 0, column: 6)
        )
        let root = SyntaxNode(
            type: "root",
            children: [left, right],
            byteRange: 0 ..< 6,
            pointRange: Point(row: 0, column: 0) ..< Point(row: 0, column: 6),
            fields: ["rhs": [right]]
        )
        let tree = SyntaxTree(root: root, source: "abcdef")

        let edit = TextEdit(
            startByte: 3,
            oldEndByte: 3,
            newEndByte: 4,
            startPoint: Point(row: 0, column: 3),
            oldEndPoint: Point(row: 0, column: 3),
            newEndPoint: Point(row: 1, column: 0)
        )
        let edited = tree.applying(edit: edit)

        #expect(edited.root.children[1].byteRange == 4 ..< 7)
        #expect(
            edited.root.children[1].pointRange == Point(
                row: 1, column: 0) ..< Point(row: 1, column: 3))
        #expect(edited.root.fields["rhs"]?.first?.byteRange == 4 ..< 7)
        #expect(
            edited.root.fields["rhs"]?.first?.pointRange == Point(
                row: 1, column: 0) ..< Point(row: 1, column: 3))
    }
}

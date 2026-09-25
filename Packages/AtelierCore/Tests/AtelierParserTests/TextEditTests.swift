import Foundation
import Testing

@testable import AtelierGrammar
@testable import AtelierParser

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

    @Test(arguments: [
        // Inserted before every node: each one shifts.
        (TextEdit(startByte: 0, oldEndByte: 0, newEndByte: 1), 2 ..< 3),
        // Replacing every node's byte with two: each one overlaps the edit and grows.
        (TextEdit(startByte: 1, oldEndByte: 2, newEndByte: 3), 1 ..< 3)
    ])
    func `An edit reaches every level of a tree too deep to walk recursively on a pool-sized stack`(
        edit: TextEdit,
        expected: Range<Int>
    ) async {
        // Walked recursively, a chain overflows a 512 KiB stack a few thousand levels down; a parse builds 16,384.
        let ranges = await onThread {
            let edited = Self.makeChain(depth: 100_000, fieldPerLevel: false).applying(edit: edit)
            return Self.levelRanges(of: edited.root)
        }
        #expect(ranges.count == 100_000)
        #expect(ranges.allSatisfy { $0 == expected })
    }

    @Test(.timeLimit(.minutes(1)))
    func `An edit rewrites each subtree of a tree whose fields repeat its children once`() {
        // The parser stores a field as a copy of a child; rewriting fields and children alike would rewrite the leaf
        // of this chain 2^63 times.
        let tree = Self.makeChain(depth: 64, fieldPerLevel: true)

        let edited = tree.applying(edit: TextEdit(startByte: 0, oldEndByte: 0, newEndByte: 1))

        #expect(Self.levelRanges(of: edited.root) == Array(repeating: 2 ..< 3, count: 64))
        var node = edited.root
        while let inner = node.fields["inner"]?.first {
            #expect(inner == node.children[0])
            node = inner
        }
    }

    /// A `depth`-level tree whose root chains down through `children[0]` to a single leaf, each node over byte 1; with
    /// `fieldPerLevel`, each branch also names its child in an `inner` field, as the parser records fields.
    private static func makeChain(depth: Int, fieldPerLevel: Bool) -> SyntaxTree {
        var node = SyntaxNode(type: "leaf", byteRange: 1 ..< 2)
        for _ in 1 ..< depth {
            node = SyntaxNode(
                type: "branch", children: [node], byteRange: 1 ..< 2, fields: fieldPerLevel ? ["inner": [node]] : [:])
        }
        return SyntaxTree(root: node, source: "xy")
    }

    /// The byte range of each level of a chain, from the root down.
    private static func levelRanges(of root: SyntaxNode) -> [Range<Int>] {
        var ranges: [Range<Int>] = []
        var node: SyntaxNode? = root
        while let current = node {
            ranges.append(current.byteRange)
            node = current.children.first
        }
        return ranges
    }
}

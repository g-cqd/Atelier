import Testing

@testable import AtelierGrammar
@testable import AtelierParser

/// A token no stack can take becomes an ERROR node that the reductions after it do not count as one of their symbols,
/// as tree-sitter's ERROR nodes are extras to its stack. Counted, it stood for the symbol below it: the reduction
/// popped the ERROR node instead, found no GOTO, and every token after it became an ERROR node too; most of the
/// ERROR bytes measured on this repository's Swift files came from that cascade.
@Suite
struct SkippedTokenTests {
    private static let grammar = GrammarDefinition(
        name: "words",
        rules: [("source", .repeat1(.symbol("word"))), ("word", .pattern("[a-z]+"))],
        extras: [.pattern(#"\s"#)])

    @Test
    func `the words after a skipped token still parse as words`() throws {
        let compiled = try ParseTableCompiler.compile(Self.grammar)
        let parser = GLRParser(
            parseTable: compiled.parseTable, lexTable: compiled.lexTable, productions: compiled.productions)

        let tree = try parser.parse("ab 12 cd 345 ef")

        #expect(tree.root.type == "source")
        #expect(Self.leaves(of: tree.root).filter { !$0.isError }.map(\.type) == ["word", "word", "word"])
        #expect(tree.errorByteCount == 5)
    }

    @Test
    func `a skipped token keeps its place among the children of the node reduced around it`() throws {
        let compiled = try ParseTableCompiler.compile(Self.grammar)
        let parser = GLRParser(
            parseTable: compiled.parseTable, lexTable: compiled.lexTable, productions: compiled.productions)

        let tree = try parser.parse("ab 1 cd")

        #expect(Self.leaves(of: tree.root).map(\.byteRange) == [0 ..< 2, 3 ..< 4, 5 ..< 7])
    }

    /// The tree's leaves in source order.
    private static func leaves(of root: SyntaxNode) -> [SyntaxNode] {
        var leaves: [SyntaxNode] = []
        var pending = [root]
        while let node = pending.popLast() {
            if node.children.isEmpty {
                if !node.byteRange.isEmpty { leaves.append(node) }
            } else {
                pending.append(contentsOf: node.children.reversed())
            }
        }
        return leaves
    }
}

import Testing

@testable import KittyParser
@testable import KittyQuery

@Suite
struct PredicatesTests {
    @Test
    func `eq predicate`() {
        let node = SyntaxNode(type: "identifier", byteRange: 0 ..< 4)
        let captures: [(node: SyntaxNode, name: String)] = [(node: node, name: "var")]
        let result = Predicates.evaluate(
            .eq(capture: "@var", value: "self"),
            captures: captures,
            source: "self"
        )
        #expect(result)
    }

    @Test
    func `not-eq predicate`() {
        let node = SyntaxNode(type: "identifier", byteRange: 0 ..< 3)
        let captures: [(node: SyntaxNode, name: String)] = [(node: node, name: "var")]
        let result = Predicates.evaluate(
            .notEq(capture: "@var", value: "self"),
            captures: captures,
            source: "abc"
        )
        #expect(result)
    }

    @Test
    func `any-of predicate`() {
        let node = SyntaxNode(type: "identifier", byteRange: 0 ..< 2)
        let captures: [(node: SyntaxNode, name: String)] = [(node: node, name: "kw")]
        let result = Predicates.evaluate(
            .anyOf(capture: "@kw", values: ["if", "for", "while"]),
            captures: captures,
            source: "if"
        )
        #expect(result)
    }

    @Test
    func `directive predicate is a no-op`() {
        let node = SyntaxNode(type: "identifier", byteRange: 0 ..< 2)
        let captures: [(node: SyntaxNode, name: String)] = [(node: node, name: "kw")]
        let result = Predicates.evaluate(
            .directive(name: "#set!", arguments: ["scope", "demo"]),
            captures: captures,
            source: "if"
        )
        #expect(result)
    }
}

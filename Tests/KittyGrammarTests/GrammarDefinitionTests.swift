import Foundation
import Testing

@testable import KittyGrammar

@Suite
struct GrammarDefinitionTests {
    @Test
    func `Rule enum variants`() {
        let sym = Rule.symbol("identifier")
        let str = Rule.string("if")
        let blank = Rule.blank
        #expect(sym == .symbol("identifier"))
        #expect(str == .string("if"))
        #expect(blank == .blank)
    }

    @Test
    func `Equality compares all stored properties`() {
        let lhs = GrammarDefinition(
            name: "shared",
            rules: [("source", .symbol("statement"))],
            extras: [.pattern("\\s+")],
            conflicts: [["source", "statement"]],
            externals: [.symbol("external_token")],
            inline: ["statement"],
            word: "identifier",
            supertypes: ["expression"],
            precedences: [[.symbol("statement")]]
        )
        let rhs = GrammarDefinition(
            name: "shared",
            rules: [("source", .string("statement"))],
            extras: [.pattern("\\s+")],
            conflicts: [["source", "statement"]],
            externals: [.symbol("external_token")],
            inline: ["statement"],
            word: "identifier",
            supertypes: ["expression"],
            precedences: [[.symbol("statement")]]
        )

        #expect(lhs != rhs)
    }
}

import Foundation
import Testing

@testable import KittyCodecs
@testable import KittyGrammar
@testable import KittyParser
@testable import KittyQuery
@testable import KittySyntax

@Suite
struct GrammarLoaderBundledGrammarTests {

    private func jsonGrammarPath() throws -> String {
        let resourcePath = try #require(KittySyntaxResources.bundle.resourcePath)
        return "\(resourcePath)/Grammars/json/grammar.json"
    }

    @Test
    func `Load bundled json grammar json name is json`() throws {
        let path = try jsonGrammarPath()
        let grammar = try GrammarLoader.load(from: path)
        #expect(grammar.name == "json")
    }

    @Test
    func `Load bundled json grammar json has expected rule names`() throws {
        let path = try jsonGrammarPath()
        let grammar = try GrammarLoader.load(from: path)
        let ruleNames = grammar.rules.map(\.name)
        let expectedNames = [
            "document", "_value", "object", "pair", "array", "string", "number", "true", "false",
            "null",
        ]
        for name in expectedNames {
            #expect(ruleNames.contains(name), "Expected rule '\(name)' in grammar")
        }
    }

    @Test
    func `Load bundled json grammar json has 2 extras whitespace pattern plus comment`() throws {
        let path = try jsonGrammarPath()
        let grammar = try GrammarLoader.load(from: path)
        #expect(grammar.extras.count == 2)
    }

    @Test
    func `Load bundled json grammar json supertypes contains _value`() throws {
        let path = try jsonGrammarPath()
        let grammar = try GrammarLoader.load(from: path)
        #expect(grammar.supertypes.contains("_value"))
    }

    @Test
    func `parse invalid JSON data throws GrammarError`() {
        #expect(throws: GrammarError.self) {
            try GrammarLoader.parse(Data("not valid json {{{".utf8))
        }
    }

    @Test
    func `Load bundled swift grammar external scanner is not required`() throws {
        let resourcePath = try #require(KittySyntaxResources.bundle.resourcePath)
        let path = "\(resourcePath)/Grammars/swift/grammar.json"
        let grammar = try GrammarLoader.load(from: path)
        #expect(grammar.name == "swift")
        #expect(grammar.externals.isEmpty)
    }
}

import AtelierScanners
import Foundation
import Testing

@testable import AtelierGrammar
@testable import AtelierParser
@testable import AtelierQuery
@testable import KittyCodecs
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
            "null"
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

    /// Swift's grammar is upstream's since 0.7.3, whose external scanner produces 33 tokens.
    @Test
    func `bundled swift grammar declares its scanner's externals`() throws {
        let resourcePath = try #require(KittySyntaxResources.bundle.resourcePath)
        let path = "\(resourcePath)/Grammars/swift/grammar.json"
        let grammar = try GrammarLoader.load(from: path)
        #expect(grammar.name == "swift")
        #expect(grammar.externals.count == 33)
    }

    @Test(arguments: BundledLanguageManifest.entries.map(\.path))
    func `every bundled grammar loads`(language: String) throws {
        let resourcePath = try #require(KittySyntaxResources.bundle.resourcePath)
        let grammar = try GrammarLoader.load(from: "\(resourcePath)/Grammars/\(language)/grammar.json")
        #expect(grammar.name == language)
    }

    /// The parser refuses a scanner whose names differ from its grammar's externals, which leaves every parse throwing.
    @Test(arguments: BundledScanners.byGrammarName.keys.sorted())
    func `every bundled scanner names its grammar's externals in order`(language: String) throws {
        let resourcePath = try #require(KittySyntaxResources.bundle.resourcePath)
        let grammar = try GrammarLoader.load(from: "\(resourcePath)/Grammars/\(language)/grammar.json")
        let scanner = try #require(BundledScanners.byGrammarName[language])
        #expect(scanner.externalNames == ParseTableCompiler.externalNames(of: grammar))
    }
}

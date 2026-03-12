import Foundation
import Testing

@testable import KittyCodecs
@testable import KittyGrammar
@testable import KittyParser
@testable import KittyQuery
@testable import KittySyntax

@Suite
struct GrammarRegistryTests {
    @Test
    func `Register and lookup by extension`() async {
        let registry = GrammarRegistry()
        await registry.register(
            GrammarRegistry.LanguageEntry(
                name: "swift", extensions: [".swift"], path: "swift"
            ))
        let entry = await registry.entry(forExtension: ".swift")
        #expect(entry?.name == "swift")
    }

    @Test
    func `Language names are sorted`() async {
        let registry = GrammarRegistry()
        await registry.register(
            GrammarRegistry.LanguageEntry(name: "swift", extensions: [".swift"], path: "swift"))
        await registry.register(
            GrammarRegistry.LanguageEntry(name: "python", extensions: [".py"], path: "python"))
        let names = await registry.languageNames
        #expect(names == ["python", "swift"])
    }

    // MARK: - New tests

    @Test
    func `entry forExtension returns nil for unregistered extension`() async {
        let registry = GrammarRegistry()
        let entry = await registry.entry(forExtension: ".xyz")
        #expect(entry == nil)
    }

    @Test
    func `entry forExtension normalises extension without leading dot`() async {
        let registry = GrammarRegistry()
        await registry.register(
            GrammarRegistry.LanguageEntry(name: "json", extensions: [".json"], path: "json"))
        let entry = await registry.entry(forExtension: "json")
        #expect(entry?.name == "json")
    }

    @Test
    func `loadManifest registers all 19 languages from bundled languages json`() async throws {
        let grammarsPath = try #require(KittySyntaxResources.bundle.resourcePath)
        let manifestPath = "\(grammarsPath)/Grammars/languages.json"
        let registry = GrammarRegistry()
        try await registry.loadManifest(from: manifestPath)
        let names = await registry.languageNames
        #expect(names.count == 19)
    }

    @Test
    func `Bundled manifest entries ship grammar and highlight resources`() throws {
        let resourcePath = try #require(KittySyntaxResources.bundle.resourcePath)

        for entry in BundledLanguageManifest.entries {
            let grammarPath = "\(resourcePath)/Grammars/\(entry.path)/grammar.json"
            let highlightsPath = "\(resourcePath)/Grammars/\(entry.path)/highlights.scm"

            #expect(
                FileManager.default.fileExists(atPath: grammarPath),
                "Missing grammar for \(entry.name)")
            #expect(
                FileManager.default.fileExists(atPath: highlightsPath),
                "Missing highlights for \(entry.name)")
        }
    }
}

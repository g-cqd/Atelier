import Foundation
import Testing

@testable import AtelierGrammarCorpus

@Suite
struct GrammarRegistryTests {
    @Test
    func `Register and lookup by extension`() async {
        let registry = GrammarRegistry.scratch()
        registry.register(
            GrammarRegistry.LanguageEntry(
                name: "swift", extensions: [".swift"], path: "swift"
            ))
        let entry = registry.entry(forExtension: ".swift")
        #expect(entry?.name == "swift")
    }

    @Test
    func `Language names are sorted`() async {
        let registry = GrammarRegistry.scratch()
        registry.register(
            GrammarRegistry.LanguageEntry(name: "swift", extensions: [".swift"], path: "swift"))
        registry.register(
            GrammarRegistry.LanguageEntry(name: "python", extensions: [".py"], path: "python"))
        let names = registry.languageNames
        #expect(names == ["python", "swift"])
    }

    // MARK: - Lookups and the bundled manifest

    @Test
    func `entry forExtension returns nil for unregistered extension`() async {
        let registry = GrammarRegistry.scratch()
        let entry = registry.entry(forExtension: ".xyz")
        #expect(entry == nil)
    }

    @Test
    func `entry forExtension normalises extension without leading dot`() async {
        let registry = GrammarRegistry.scratch()
        registry.register(
            GrammarRegistry.LanguageEntry(name: "json", extensions: [".json"], path: "json"))
        let entry = registry.entry(forExtension: "json")
        #expect(entry?.name == "json")
    }

    @Test
    func `an extension registered without its dot is found`() {
        let registry = GrammarRegistry.scratch()
        registry.register(GrammarRegistry.LanguageEntry(name: "elvish", extensions: ["elv"], path: "elvish"))

        #expect(registry.entry(forExtension: ".elv")?.name == "elvish")
        #expect(registry.entry(forFilename: "build.elv")?.name == "elvish")
    }

    @Test
    func `an extension registered in capitals is found by a file name`() {
        let registry = GrammarRegistry.scratch()
        registry.register(GrammarRegistry.LanguageEntry(name: "elvish", extensions: [".ELV"], path: "elvish"))

        #expect(registry.entry(forFilename: "build.elv")?.name == "elvish")
    }

    @Test
    func `a registered dotfile name is found by its full path`() {
        let registry = GrammarRegistry.scratch()
        registry.register(GrammarRegistry.LanguageEntry(name: "bash", extensions: [".bashrc"], path: "bash"))

        #expect(registry.entry(forFilename: "/home/user/.bashrc")?.name == "bash")
    }

    @Test
    func `loadManifest registers all 19 languages from bundled languages json`() async throws {
        let manifestPath = try GrammarCorpus.bundled().manifestURL.path
        let registry = GrammarRegistry.scratch()
        try registry.loadManifest(from: manifestPath)
        let names = registry.languageNames
        #expect(names.count == 19)
    }

    @Test
    func `Bundled manifest entries ship grammar and highlight resources`() throws {
        let corpus = try GrammarCorpus.bundled()

        for entry in try corpus.manifest().entries {
            let grammarPath = corpus.grammarURL(for: entry).path
            let highlightsPath = corpus.highlightsURL(for: entry).path

            #expect(
                FileManager.default.fileExists(atPath: grammarPath),
                "Missing grammar for \(entry.name)")
            #expect(
                FileManager.default.fileExists(atPath: highlightsPath),
                "Missing highlights for \(entry.name)")
        }
    }

    @Test
    func `entry forLanguage finds a registered language by name`() {
        let registry = GrammarRegistry.scratch()
        registry.register(
            GrammarRegistry.LanguageEntry(
                name: "ruby", extensions: [".rb", ".ruby"], path: "ruby"))

        let entry = registry.entry(forLanguage: "ruby")
        #expect(entry?.name == "ruby")
        #expect(entry?.extensions == [".rb", ".ruby"])
        #expect(entry?.path == "ruby")
    }

    @Test
    func `entry forLanguage returns nil for unregistered language`() {
        let registry = GrammarRegistry.scratch()
        #expect(registry.entry(forLanguage: "elvish") == nil)
    }

    /// The lookup a language detection makes before the bundled manifest.
    @Test
    func `entry forFilename extracts extension and looks up`() {
        let registry = GrammarRegistry.scratch()
        registry.register(
            GrammarRegistry.LanguageEntry(
                name: "elvish", extensions: [".elv"], path: "elvish"))

        #expect(registry.entry(forFilename: "build.elv")?.name == "elvish")
        #expect(registry.entry(forFilename: "BUILD.ELV")?.name == "elvish")
        #expect(registry.entry(forFilename: "noext")?.name == nil)
        #expect(registry.entry(forFilename: "untracked.foo")?.name == nil)
    }
}

extension GrammarRegistry {
    /// A registry for tests that compile nothing, caching under a directory of its own.
    static func scratch() -> GrammarRegistry {
        GrammarRegistry(
            cacheDirectory: FileManager.default.temporaryDirectory.appending(
                path: "grammar-registry-\(UUID().uuidString)"))
    }
}

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
        registry.register(
            GrammarRegistry.LanguageEntry(
                name: "swift", extensions: [".swift"], path: "swift"
            ))
        let entry = registry.entry(forExtension: ".swift")
        #expect(entry?.name == "swift")
    }

    @Test
    func `Language names are sorted`() async {
        let registry = GrammarRegistry()
        registry.register(
            GrammarRegistry.LanguageEntry(name: "swift", extensions: [".swift"], path: "swift"))
        registry.register(
            GrammarRegistry.LanguageEntry(name: "python", extensions: [".py"], path: "python"))
        let names = registry.languageNames
        #expect(names == ["python", "swift"])
    }

    // MARK: - New tests

    @Test
    func `entry forExtension returns nil for unregistered extension`() async {
        let registry = GrammarRegistry()
        let entry = registry.entry(forExtension: ".xyz")
        #expect(entry == nil)
    }

    @Test
    func `entry forExtension normalises extension without leading dot`() async {
        let registry = GrammarRegistry()
        registry.register(
            GrammarRegistry.LanguageEntry(name: "json", extensions: [".json"], path: "json"))
        let entry = registry.entry(forExtension: "json")
        #expect(entry?.name == "json")
    }

    @Test
    func `loadManifest registers all 19 languages from bundled languages json`() async throws {
        let grammarsPath = try #require(KittySyntaxResources.bundle.resourcePath)
        let manifestPath = "\(grammarsPath)/Grammars/languages.json"
        let registry = GrammarRegistry()
        try registry.loadManifest(from: manifestPath)
        let names = registry.languageNames
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

    /// Audit D1 — confirm the new `entry(forLanguage:)` method (the
    /// primary dispatch path for `SyntaxArtifactsCache`) finds a
    /// registered entry by name even though storage is keyed by
    /// extension.
    @Test
    func `entry forLanguage finds a registered language by name`() {
        let registry = GrammarRegistry()
        registry.register(
            GrammarRegistry.LanguageEntry(
                name: "ruby", extensions: [".rb", ".ruby"], path: "ruby"))

        let entry = registry.entry(forLanguage: "ruby")
        #expect(entry?.name == "ruby")
        #expect(entry?.extensions == [".rb", ".ruby"])
        #expect(entry?.path == "ruby")
    }

    /// Audit D1 — confirm `entry(forLanguage:)` returns nil for an
    /// unregistered language. The cache then falls back to the
    /// bundled manifest at the SyntaxArtifactsCache layer.
    @Test
    func `entry forLanguage returns nil for unregistered language`() {
        let registry = GrammarRegistry()
        #expect(registry.entry(forLanguage: "elvish") == nil)
    }

    /// Audit D1 — the `LanguageEntry.init(bundled:)` bridge produces
    /// a registry-shaped entry equivalent to the bundled one. Used by
    /// `SyntaxArtifactsCache` to unify the registry / bundled fallback
    /// paths into a single resolution result.
    @Test
    func `bundled entry bridges into LanguageEntry verbatim`() {
        let bundled = BundledLanguageEntry(
            name: "go", extensions: [".go"], path: "go")
        let registry = GrammarRegistry.LanguageEntry(bundled: bundled)
        #expect(registry.name == "go")
        #expect(registry.extensions == [".go"])
        #expect(registry.path == "go")
    }

    /// Audit A.4/F10 — `entry(forFilename:)` is the surface
    /// `LanguageHighlighter.detectLanguage(for:)` consults so file
    /// opens can dispatch to runtime-registered grammars before the
    /// bundled fallback.
    @Test
    func `entry forFilename extracts extension and looks up`() {
        let registry = GrammarRegistry()
        registry.register(
            GrammarRegistry.LanguageEntry(
                name: "elvish", extensions: [".elv"], path: "elvish"))

        #expect(registry.entry(forFilename: "build.elv")?.name == "elvish")
        #expect(registry.entry(forFilename: "BUILD.ELV")?.name == "elvish")
        #expect(registry.entry(forFilename: "noext")?.name == nil)
        #expect(registry.entry(forFilename: "untracked.foo")?.name == nil)
    }
}

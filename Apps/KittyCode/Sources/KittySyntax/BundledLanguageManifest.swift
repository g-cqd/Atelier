import AtelierGrammarCorpus
import Foundation
import os

/// The manifest of the grammars KittyCode bundles, read once from the corpus.
enum BundledLanguageManifest {
    /// The bundled manifest; nil when the corpus is missing, or, with a fault logged, when its manifest is unreadable
    /// or corrupt, which leaves every grammar highlighter disabled.
    static let manifest: GrammarManifest? = loadManifest()

    static var entries: [GrammarRegistry.LanguageEntry] {
        manifest?.entries ?? []
    }

    static func entry(forLanguage language: String) -> GrammarRegistry.LanguageEntry? {
        manifest?.entry(forLanguage: language)
    }

    static func entry(forFilename filename: String) -> GrammarRegistry.LanguageEntry? {
        manifest?.entry(forFilename: filename)
    }

    /// Reports a missing or corrupt bundled manifest.
    private static let logger = Logger(
        subsystem: "kittycode.kittysyntax", category: "bundled-language-manifest")

    private static func loadManifest() -> GrammarManifest? {
        guard let corpus = KittySyntaxResources.corpus else { return nil }
        do {
            return try corpus.manifest()
        } catch {
            logger.fault("languages.json unusable: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}

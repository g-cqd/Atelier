import Foundation
import os

/// The manifest of the grammars KittyCode bundles, read once from the resource bundle.
enum BundledLanguageManifest {
    /// The bundled manifest; nil, with a fault logged, when it is missing or corrupt, which leaves every grammar
    /// highlighter disabled.
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
        guard
            let manifestURL = KittySyntaxResources.bundle.url(
                forResource: "languages",
                withExtension: "json",
                subdirectory: "Grammars"
            )
        else {
            logger.fault("languages.json missing from KittySyntax resource bundle")
            return nil
        }
        let data: Data
        do {
            data = try Data(contentsOf: manifestURL)
        } catch {
            logger.fault(
                "languages.json read failed at \(manifestURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
        do {
            return try GrammarManifest.decode(data)
        } catch {
            logger.fault(
                "languages.json decode failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

import AtelierGrammarCorpus
import Foundation
import os

/// The grammars KittyCode highlights with: AtelierCore's bundled corpus, found once.
/// Tests use `@testable import KittySyntax` to reach this.
enum KittySyntaxResources {
    /// The bundled corpus; nil, with a fault logged, when its bundle is missing, which leaves every language on the
    /// lexical highlighter.
    static let corpus: GrammarCorpus? = locateCorpus()

    /// The bundled grammars: one directory per language, and `languages.json`.
    static var grammarsDirectory: URL? {
        corpus?.grammarsDirectory
    }

    /// The directory holding `Grammars/`; nil without a corpus.
    static var resourcePath: String? {
        grammarsDirectory?.deletingLastPathComponent().path
    }

    /// Whether the bundled corpus holds `name` in `entry`'s directory.
    static func hasResource(_ name: String, for entry: GrammarRegistry.LanguageEntry) -> Bool {
        guard let corpus else { return false }
        return FileManager.default.fileExists(atPath: corpus.directory(for: entry).appending(path: name).path)
    }

    private static let logger = Logger(subsystem: "kittycode.kittysyntax", category: "grammar-corpus")

    private static func locateCorpus() -> GrammarCorpus? {
        do {
            return try GrammarCorpus.bundled()
        } catch {
            logger.fault("grammar corpus missing: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}

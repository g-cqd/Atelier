import AtelierGrammarCorpus
import Foundation

/// The bundle of the grammars KittyCode highlights with, AtelierCore's grammar corpus.
/// Tests use `@testable import KittySyntax` to reach this.
enum KittySyntaxResources {
    static let bundle: Bundle = GrammarCorpus.bundle

    /// The bundled grammars: one directory per language, and `languages.json`.
    static var grammarsDirectory: URL? {
        bundle.resourceURL?.appending(path: "Grammars", directoryHint: .isDirectory)
    }
}

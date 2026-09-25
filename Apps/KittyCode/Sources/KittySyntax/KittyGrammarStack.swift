import AtelierParser
import AtelierScanners
import Foundation

extension GrammarRegistry {
    /// KittyCode's registry, which the highlighter consults before the bundled manifest. It caches compiled tables
    /// under the temporary directory's `kittycode-cache`.
    public static let shared = GrammarRegistry(
        cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("kittycode-cache"),
        bundledManifest: BundledLanguageManifest.manifest ?? .empty)

    /// The bundled scanner for a grammar, when one has been ported and registered.
    func scannerType(forGrammar name: String) -> (any GrammarExternalScanner.Type)? {
        BundledScanners.byGrammarName[name]
    }
}

extension SyntaxArtifactsCache {
    /// KittyCode's artifacts, loaded through `GrammarRegistry.shared` from the bundled grammars.
    static let shared = SyntaxArtifactsCache(
        registry: .shared, grammarsDirectory: KittySyntaxResources.grammarsDirectory)
}

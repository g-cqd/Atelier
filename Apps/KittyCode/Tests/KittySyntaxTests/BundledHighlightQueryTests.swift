import AtelierGrammarCorpus
import Foundation
import Testing

@testable import AtelierQuery
@testable import KittySyntax

/// Every bundled `highlights.scm` parses, so a typo cannot leave a language unhighlighted without a failing test.
struct BundledHighlightQueryTests {
    @Test(arguments: BundledLanguageManifest.entries.map(\.path))
    func `bundled highlight query parses`(language: String) throws {
        let resourcePath = try #require(KittySyntaxResources.resourcePath)
        let source = try String(contentsOfFile: "\(resourcePath)/Grammars/\(language)/highlights.scm", encoding: .utf8)

        let query = try QueryParser.parse(source)
        #expect(!query.patterns.isEmpty)
    }
}

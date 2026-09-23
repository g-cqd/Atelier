import Foundation
import Testing

@testable import AtelierQuery
@testable import KittySyntax

/// Every bundled `highlights.scm` parses, so a typo cannot leave a language unhighlighted without a failing test.
struct BundledHighlightQueryTests {
    /// Languages whose query uses syntax `QueryParser` does not read yet: JavaScript's one-argument
    /// `#is-not? local`, Ruby's `#is-not?` with two arguments, Kotlin's grouped alternations and YAML's field inside
    /// a wildcard node.
    private static let queriesUsingUnsupportedSyntax: Set<String> = ["javascript", "kotlin", "ruby", "yaml"]

    @Test(arguments: BundledLanguageManifest.entries.map(\.path))
    func `bundled highlight query parses`(language: String) throws {
        let resourcePath = try #require(KittySyntaxResources.bundle.resourcePath)
        let source = try String(contentsOfFile: "\(resourcePath)/Grammars/\(language)/highlights.scm", encoding: .utf8)

        if Self.queriesUsingUnsupportedSyntax.contains(language) {
            withKnownIssue("QueryParser does not read all of this query's syntax yet") {
                _ = try QueryParser.parse(source)
            }
        } else {
            let query = try QueryParser.parse(source)
            #expect(!query.patterns.isEmpty)
        }
    }
}

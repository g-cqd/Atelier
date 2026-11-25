import AtelierSwiftSyntax
import AtelierSyntaxModel
import Testing

@testable import AtelierDocIndex

/// Hover's index reads a changeset file's declarations from the facts store, and documents exactly what its own parse
/// documented (PERF-11 step 3).
struct DocCommentIndexStoreTests {
    private static let content = """
        /// Loads the configuration.
        func loadConfig() -> Config { Config() }
        /** A setting. */
        struct Config {
            /// Its name.
            var `name` = "a", other = 1
        }
        enum Mode {
            /// Fast.
            case fast, slow
        }
        """

    @Test
    func `a file the store knows is not parsed again, and documents what a parse documents`() async throws {
        let store = SyntaxFactsStore()
        let revision = SourceRevision(documentID: "a.swift", language: .swift, key: .content("blob"))
        _ = await SwiftSyntaxFacts.facts(for: revision, text: Self.content, in: store)
        let stored = DocCommentIndex(store: store)
        let parsed = DocCommentIndex()
        let file = DocIndexFile(uri: "file:///a.swift", content: Self.content, blobID: "blob")

        try await stored.upsert([file])
        try await parsed.upsert([file])

        #expect(store.extractions == 1)
        for name in ["loadConfig", "Config", "name", "other", "fast", "slow", "Mode"] {
            let fromStore = await stored.documentation(forIdentifier: name, preferringURI: nil)
            let fromParse = await parsed.documentation(forIdentifier: name, preferringURI: nil)
            #expect(fromStore == fromParse, "\(name)")
        }
        #expect(await stored.documentation(forIdentifier: "fast", preferringURI: nil).map(\.markdown) == ["Fast."])
    }

    @Test
    func `a file without a blob id is parsed for its declarations alone`() async throws {
        let store = SyntaxFactsStore()
        let index = DocCommentIndex(store: store)

        try await index.upsert([DocIndexFile(uri: "file:///a.swift", content: Self.content)])

        #expect(store.extractions == 0)
        #expect(await index.documentation(forIdentifier: "loadConfig", preferringURI: nil).count == 1)
    }
}

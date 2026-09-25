import AtelierDocComment
import AtelierSyntaxModel
import Testing

@testable import AtelierDocIndex

/// The index and its hover beyond Swift: TypeScript, JavaScript and Go through the lexical extractor (HOVER-16).
struct DocCommentIndexLanguagesTests {
    private static let store = """
        /**
         * Loads the user named by `id`.
         * @param id The user's identifier.
         */
        export async function load(id: string): Promise<User> {}
        """

    private static let caller = """
        import { load } from "./store";
        const user = await load("42");
        """

    private static let goStore = """
        package store

        // Load reads a user from disk.
        func load(id string) (*User, error) { return nil, nil }
        """

    @Test
    func `a JSDoc block answers a hover in another TypeScript or JavaScript file`() async throws {
        let index = DocCommentIndex()
        try await index.update(files: [
            DocIndexFile(uri: "file:///web/store.ts", content: Self.store),
            DocIndexFile(uri: "file:///web/app.js", content: Self.caller)
        ])
        let provider = DocIndexHoverProvider(index: index)

        let hover = try await provider.hover(
            HoverQuery(documentURI: "file:///web/app.js", content: Self.caller, line: 1, utf16Column: 21))

        #expect(hover?.source == .docIndex)
        #expect(
            hover?.markdown == """
                ```typescript
                export async function load(id: string): Promise<User>
                ```

                Loads the user named by `id`.

                - Parameter id: The user's identifier.
                """)
    }

    @Test
    func `a Go hover lists only Go declarations of its name`() async throws {
        let index = DocCommentIndex()
        let goCaller = "package main\n\nfunc main() { load(\"42\") }\n"
        try await index.update(files: [
            DocIndexFile(uri: "file:///web/store.ts", content: Self.store),
            DocIndexFile(uri: "file:///cmd/store.go", content: Self.goStore),
            DocIndexFile(uri: "file:///cmd/main.go", content: goCaller)
        ])
        let provider = DocIndexHoverProvider(index: index)

        let hover = try await provider.hover(
            HoverQuery(documentURI: "file:///cmd/main.go", content: goCaller, line: 2, utf16Column: 15))

        #expect(
            hover?.markdown == """
                ```go
                func load(id string) (*User, error)
                ```

                Load reads a user from disk.
                """)
    }

    @Test
    func `a file's entries follow its content, with a blob id or without one`() async throws {
        let index = DocCommentIndex()
        func markdown() async -> [String] {
            await index.documentation(forIdentifier: "parse", preferringURI: nil).map(\.markdown)
        }
        try await index.upsert([DocIndexFile(uri: "file:///a.go", content: "// Parse reads.\nfunc parse() {}\n")])
        try await index.upsert([
            DocIndexFile(uri: "atelier-blob://b1/b.ts", content: "/** Old. */\nfunction parse() {}\n", blobID: "b1")
        ])
        #expect(await markdown().sorted() == ["Old.", "Parse reads."])

        try await index.upsert([DocIndexFile(uri: "file:///a.go", content: "// Parse writes.\nfunc parse() {}\n")])
        try await index.upsert([
            DocIndexFile(uri: "atelier-blob://b1/b.ts", content: "/** New. */\nfunction parse() {}\n", blobID: "b2")
        ])

        #expect(await markdown().sorted() == ["New.", "Parse writes."])
    }

    @Test
    func `a language outside the extractor table has no entries and no hover`() async throws {
        let python = "# Adds.\ndef add(a, b): return a + b\nadd(1, 2)\n"
        let index = DocCommentIndex(extractors: [.go: LexicalDeclarationExtractor()])
        try await index.update(files: [
            DocIndexFile(uri: "file:///store.ts", content: Self.store),
            DocIndexFile(uri: "file:///tool.py", content: python)
        ])

        #expect(await index.documentation(forIdentifier: "load", preferringURI: nil).isEmpty)
        #expect(!index.indexes(.typescript))
        #expect(index.indexes(.go))
        #expect(index.indexes(.swift))
        let hover = try await DocIndexHoverProvider(index: index)
            .hover(
                HoverQuery(documentURI: "file:///tool.py", content: python, line: 2, utf16Column: 1))
        #expect(hover == nil)
    }
}

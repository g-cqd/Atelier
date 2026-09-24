import AtelierSyntaxModel
import SwiftParser
import SwiftSyntax
import Synchronization
import Testing

@testable import AtelierDocIndex

/// Counts the documents parsed.
private final class ParseCounter: Sendable {
    private let count = Mutex(0)

    var value: Int { count.withLock { $0 } }

    func parse(_ content: String) -> SourceFileSyntax {
        count.withLock { $0 += 1 }
        return Parser.parse(source: content)
    }
}

/// A pointer resting over one document parses it once, however many hovers it makes there (Core S5).
struct ParsedSourceCacheTests {
    private let parses = ParseCounter()

    private func makeProvider() async throws -> DocIndexHoverProvider {
        let index = DocCommentIndex()
        try await index.upsert([
            DocIndexFile(uri: "file:///decl.swift", content: "/// Loads.\nfunc load() {}\n/// Saves.\nfunc save() {}")
        ])
        let sources = ParsedSourceCache { [parses] content in parses.parse(content) }
        return DocIndexHoverProvider(index: index, side: .both, sources: sources)
    }

    /// "load" sits at columns 8..<12 of line 0, and "save" at 8..<12 of line 1.
    private let caller = "let a = load()\nlet b = save()\n"

    private func hover(_ provider: DocIndexHoverProvider, _ content: String, line: Int) async throws -> String? {
        let query = HoverQuery(documentURI: "file:///use.swift", content: content, line: line, utf16Column: 9)
        return try await provider.hover(query)?.markdown
    }

    @Test
    func `a document that is not Swift is never parsed`() async throws {
        let provider = try await makeProvider()
        let query = HoverQuery(documentURI: "file:///script.py", content: "a = load()\n", line: 0, utf16Column: 5)

        let content = try await provider.hover(query)

        #expect(content == nil)
        #expect(parses.value == 0)
    }

    @Test
    func `two hovers in the same document parse it once`() async throws {
        let provider = try await makeProvider()

        let load = try await hover(provider, caller, line: 0)
        let save = try await hover(provider, caller, line: 1)

        #expect(load?.contains("Loads.") == true)
        #expect(save?.contains("Saves.") == true)
        #expect(parses.value == 1)
    }

    @Test
    func `a hover in another document parses that one`() async throws {
        let provider = try await makeProvider()
        let other = "let c = save()\n"

        _ = try await hover(provider, caller, line: 0)
        let save = try await hover(provider, other, line: 0)

        #expect(save?.contains("Saves.") == true)
        #expect(parses.value == 2)
    }
}

import AtelierGrammarCorpus
import AtelierLexers
import AtelierSyntaxModel
import Synchronization
import Testing

@testable import KittySyntax

/// The grammar tier as a `HighlightEngine`, next to the lexical one.
struct GrammarHighlightEngineTests {
    @Test
    func `the engine is the structural tier and declines what has no grammar`() {
        let engine = GrammarHighlightEngine()
        #expect(engine.layer == .structural)
        #expect(LexicalHighlightEngine().layer == .lexical)
        #expect(!engine.supports(.plain))
        #expect(!engine.supports(.objectiveC))
        #expect(GrammarHighlightEngine.grammarName(of: .shell) == "bash")
        #expect(GrammarHighlightEngine.grammarName(of: .cpp) == "cpp")
    }

    @Test
    func `a loaded grammar is supported and its tokens are the session's structural tokens`() async {
        let available = await LanguageHighlighter.ensureArtifacts(for: "json")
        let engine = GrammarHighlightEngine()
        let source = Array("{\"a\": 1}".utf8)
        #expect(available)
        #expect(engine.supports(.json))
        let session = LanguageHighlighter.makeSession(language: "json", preferGrammar: true)
        #expect(
            engine.highlight(utf8: source, language: .json) == session.highlightDocumentTokens(source: "{\"a\": 1}"))
        // The grammar parses the object, so its query colours the key and the number.
        let roles = Set(engine.highlight(utf8: source, language: .json).map(\.role))
        #expect(roles.isSuperset(of: [.property, .number]))
    }

    @Test
    func `the grammar tier colours a text as the session's structural tokens do`() async throws {
        let source = "{\n  \"a\": 1,\n  \"b\": [true, null]\n}\n"
        var lineRanges: [Range<Int>] = []
        var start = 0
        for (offset, byte) in source.utf8.enumerated() where byte == UInt8(ascii: "\n") {
            lineRanges.append(start ..< offset)
            start = offset + 1
        }
        lineRanges.append(start ..< source.utf8.count)
        let request = TierRequest(
            revision: SourceRevision(documentID: "a.json", language: .json, key: .version(1)), text: source,
            lineRanges: lineRanges, visibleLines: 0 ..< lineRanges.count)
        let updates = UpdateLog()

        try await LanguageHighlighter.grammarTier().run(request) { updates.append($0) }

        let session = LanguageHighlighter.makeSession(language: "json", preferGrammar: true)
        let expected = LineTokens(
            HighlightMerger.merge(session.highlightDocumentTokens(source: source), sourceByteCount: source.utf8.count),
            lineRanges: lineRanges)
        let update = try #require(updates.all.first)
        #expect(updates.all.count == 1)
        #expect(update.layer == .structural)
        #expect(update.tokens == expected)
        #expect(!session.highlightDocumentTokens(source: source).isEmpty)
    }
}

/// The updates a tier emitted, in order.
private final class UpdateLog: Sendable {
    private let updates = Mutex<[TierUpdate]>([])

    var all: [TierUpdate] { updates.withLock { $0 } }

    func append(_ update: TierUpdate) {
        updates.withLock { $0.append(update) }
    }
}

import AemiTestKit
import AtelierHighlighting
import AtelierSwiftSyntax
import AtelierSyntaxModel
import Foundation
import Testing

@testable import AtelierLSP

/// The semantic tier over swift-syntax's, merged per line as a pane paints them (PERF-11 step 8's acceptance).
@Suite
struct SemanticTierMergeTests {
    private static let text = "let value = compute()"
    private static let revision = SourceRevision(documentID: "A.swift", language: .swift, key: .content("blob"))
    private static let initialize: JSONValue = .object([
        "capabilities": .object([
            "semanticTokensProvider": .object([
                "legend": .object([
                    "tokenTypes": .array([.string("keyword"), .string("variable"), .string("function")]),
                    "tokenModifiers": .array([])
                ]),
                "full": .bool(true)
            ])
        ])
    ])
    /// `let` a keyword, `value` a variable, `compute` a function.
    private static let tokens: JSONValue = .object([
        "data": .array([0, 0, 3, 0, 0, 0, 4, 5, 1, 0, 0, 8, 7, 2, 0].map { JSONValue.number(Double($0)) })
    ])

    private func makeSession(_ factory: ScriptedConnectionFactory, clock: TestClock = TestClock())
        -> LanguageServerSession
    {
        LanguageServerSession(
            configuration: LanguageServerSession.Configuration(
                serverExecutable: URL(filePath: "/usr/bin/true"), workspaceRoot: URL(filePath: "/repo")),
            clock: clock
        ) { _ in await factory.make() }
    }

    private func semanticTier(_ session: LanguageServerSession) -> SemanticTokenTier {
        SemanticTokenTier { _ in
            SemanticTokenTier.Document(session: session, uri: "file:///repo/A.swift", languageID: "swift")
        }
    }

    /// The first line's merged tokens once `tiers` ran on the text; `whileRunning` runs beside the job.
    private func merged(
        _ tiers: [any AtelierHighlighting.HighlightTier], whileRunning: @Sendable () async throws -> Void = {}
    ) async throws -> [LineToken] {
        let request = TierRequest(
            revision: Self.revision, text: Self.text, lineRanges: [0 ..< Self.text.utf8.count], visibleLines: 0 ..< 1)
        let (events, run) = HighlightTiers.events(request, tiers: tiers, clock: TestClock())
        async let running: Void = run()
        try await whileRunning()
        var layered = LayeredLineTokens(lineCount: 1)
        for await event in events {
            if case .update(let update) = event { layered.apply(update) }
        }
        await running
        return try #require(layered.merged(line: 0))
    }

    private func role(at start: UInt32, in tokens: [LineToken]) -> HighlightRole? {
        tokens.first { $0.start <= start && start < $0.start + $0.length }?.role
    }

    @Test
    func `names take the semantic tier's colours while keywords keep swift-syntax's`() async throws {
        let factory = ScriptedConnectionFactory(answering: [
            "initialize": Self.initialize, "textDocument/semanticTokens/full": Self.tokens, "shutdown": .null
        ])
        let session = makeSession(factory)
        let syntaxOnly = try await merged([SwiftSyntaxTier()])

        let both = try await merged([SwiftSyntaxTier(), semanticTier(session)])

        #expect(role(at: 0, in: both) == role(at: 0, in: syntaxOnly))
        #expect(role(at: 0, in: both) == .keyword)
        #expect(role(at: 4, in: both) == .variable)
        #expect(role(at: 12, in: both) == .function)
        await session.shutdown()
    }

    @Test(.timeLimit(.minutes(1)))
    func `a server that does not answer leaves swift-syntax's colours`() async throws {
        let factory = ScriptedConnectionFactory(answering: ["initialize": Self.initialize, "shutdown": .null])
        let clock = TestClock()
        let session = makeSession(factory, clock: clock)
        let syntaxOnly = try await merged([SwiftSyntaxTier()])

        let both = try await merged([SwiftSyntaxTier(), semanticTier(session)]) {
            await factory.waitForGeneration(1)
            let transport = await factory.transport(at: 0)
            await transport.sink.waitForCount(4)
            try await clock.waitForSleepers(atLeast: 1)
            clock.advance(by: session.requestTimeout)
        }

        #expect(both == syntaxOnly)
        await session.shutdown()
    }
}

import AemiTestKit
import AtelierHighlighting
import AtelierLexers
import AtelierSwiftSyntax
import AtelierSyntaxModel
import Foundation
import Synchronization
import Testing

/// A tier a test scripts: it emits one update over every line, after an optional wait, or throws.
private struct ScriptedTier: AtelierHighlighting.HighlightTier {
    enum Script: Sendable {
        case emit
        case wait(AsyncGate)
        case fail(TierFailure)
        /// Waits until cancelled, then records that it was and throws.
        case block(AsyncEventProbe<HighlightLayer>)
    }

    let layer: HighlightLayer
    var coverage: TierCoverage = .complete
    var deadline: Duration?
    let script: Script

    func supports(_ language: Language) -> Bool { true }

    func run(_ request: TierRequest, emit: (TierUpdate) async -> Void) async throws {
        switch script {
            case .emit: break
            case .wait(let gate): try await gate.waitUntilOpen()
            case .fail(let failure): throw failure
            case .block(let cancelled):
                do {
                    try await AsyncGate().waitUntilOpen()
                } catch {
                    cancelled.record(layer)
                    throw error
                }
        }
        let lines = 0 ..< request.lineRanges.count
        await emit(
            TierUpdate(
                layer: layer, coverage: coverage, revision: request.revision, lines: lines,
                tokens: LineTokens(emptyLines: lines.count)))
    }
}

/// The tier job runs every supported tier at once, each on its own (PERF-11 step 2).
struct HighlightTiersTests {
    private static let text = (0 ..< 10).map { "let value\($0) = \"text\" // note" }.joined(separator: "\n") + "\n"

    private static func request(visible: Range<Int> = 0 ..< 10, language: Language = .swift) -> TierRequest {
        var ranges: [Range<Int>] = []
        var start = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).dropLast() {
            ranges.append(start ..< start + line.utf8.count)
            start += line.utf8.count + 1
        }
        return TierRequest(
            revision: SourceRevision(documentID: "a.swift", language: language, key: .content("blob")), text: text,
            lineRanges: ranges, visibleLines: visible)
    }

    @Test
    func `a tier that throws or passes its deadline leaves the other tiers' updates`() async throws {
        let clock = TestClock()
        let gate = AsyncGate()
        let events = AsyncEventProbe<TierEvent>()
        let tiers: [any AtelierHighlighting.HighlightTier] = [
            ScriptedTier(layer: .lexical, script: .emit),
            ScriptedTier(layer: .structural, script: .fail(.gate("error nodes"))),
            ScriptedTier(layer: .syntactic, deadline: .milliseconds(200), script: .wait(gate))
        ]

        async let job: Void = HighlightTiers.run(Self.request(), tiers: tiers, clock: clock) { events.record($0) }
        try await clock.waitForSleepers(atLeast: 1)
        clock.advance(by: .milliseconds(200))
        await job
        gate.open()

        let recorded = events.events
        #expect(recorded.contains { if case .update(let update) = $0 { update.layer == .lexical } else { false } })
        #expect(recorded.contains { if case .finished(.lexical) = $0 { true } else { false } })
        #expect(recorded.contains { if case .failed(.structural, .gate) = $0 { true } else { false } })
        #expect(recorded.contains { if case .failed(.syntactic, .deadline) = $0 { true } else { false } })
        #expect(!recorded.contains { if case .update(let update) = $0 { update.layer == .syntactic } else { false } })
    }

    @Test
    func `a slow tier does not delay a fast one`() async throws {
        let gate = AsyncGate()
        let events = AsyncEventProbe<TierEvent>()
        let tiers: [any AtelierHighlighting.HighlightTier] = [
            ScriptedTier(layer: .syntactic, script: .wait(gate)), ScriptedTier(layer: .lexical, script: .emit)
        ]

        async let job: Void = HighlightTiers.run(Self.request(), tiers: tiers, clock: TestClock()) {
            events.record($0)
        }
        let first = try await events.wait(forAtLeast: 2)
        gate.open()
        await job

        #expect(
            first.prefix(2)
                .allSatisfy { event in
                    switch event {
                        case .update(let update): update.layer == .lexical
                        case .finished(let layer): layer == .lexical
                        case .failed: false
                    }
                })
        #expect(events.events.count == 4)
    }

    @Test
    func `every tier emits the visible lines first`() async throws {
        let events = AsyncEventProbe<TierEvent>()
        let tiers: [any AtelierHighlighting.HighlightTier] = [LexicalTier(), SwiftSyntaxTier()]

        await HighlightTiers.run(Self.request(visible: 4 ..< 7), tiers: tiers, clock: TestClock()) {
            events.record($0)
        }

        for layer in [HighlightLayer.lexical, .syntactic] {
            let lines = events.events.compactMap { event -> Range<Int>? in
                guard case .update(let update) = event, update.layer == layer else { return nil }
                return update.lines
            }
            #expect(lines == [4 ..< 7, 7 ..< 10, 0 ..< 4], "\(layer)")
        }
    }

    @Test
    func `a tier that does not support the language never runs`() async {
        let events = AsyncEventProbe<TierEvent>()

        await HighlightTiers.run(
            Self.request(language: .json), tiers: [SwiftSyntaxTier(), LexicalTier()], clock: TestClock()
        ) { events.record($0) }

        #expect(
            events.events.allSatisfy { event in
                switch event {
                    case .update(let update): update.layer == .lexical
                    case .finished(let layer), .failed(let layer, _): layer == .lexical
                }
            })
    }

    @Test
    func `cancelling the job stops every tier`() async throws {
        let cancelled = AsyncEventProbe<HighlightLayer>()
        let tiers: [any AtelierHighlighting.HighlightTier] = [
            ScriptedTier(layer: .lexical, script: .block(cancelled)),
            ScriptedTier(layer: .syntactic, script: .block(cancelled))
        ]
        let events = AsyncEventProbe<TierEvent>()

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await HighlightTiers.run(Self.request(), tiers: tiers, clock: TestClock()) { events.record($0) }
            }
            group.cancelAll()
        }

        #expect(Set(try await cancelled.wait(forAtLeast: 2)) == [.lexical, .syntactic])
        #expect(events.events.isEmpty)
    }

    @Test
    func `the job's stream finishes with the job`() async {
        let (events, run) = HighlightTiers.events(Self.request(), tiers: [LexicalTier()], clock: TestClock())

        async let job: Void = run()
        var received = 0
        for await _ in events { received += 1 }
        await job

        #expect(received == 2)
    }
}

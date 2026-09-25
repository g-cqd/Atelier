import AtelierHighlighting
import AtelierSyntaxModel
import Foundation
import Synchronization
import Testing

@testable import AtelierGrammarCorpus

/// Opt-in guard of the grammar tier's 250 ms CPU deadline (PERF-11 step 5, acceptance 4), on inputs the repository
/// pins: the Python grammar's own `grammar.json` (146 KB of JSON) and GitDiffViewer's `main_actor_budget.py` (8 KB of
/// Python). It also reports what 50 KB of plain Go written here gives: plain Go parses in time, while Go's own
/// `net/http/request.go` took 35 s of CPU in the grammar assessment, which the deadline stops, so whether a Go side
/// takes its grammar's colour depends on the side, and the predictor learns from the sides that stop.
///
/// `GDV_BENCH=1 swift test --filter GrammarTierDeadlineBenchmark`, in release for numbers that mean anything.
struct GrammarTierDeadlineBenchmark {
    private static let repository = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// 50 KB of plain Go: one small function after another.
    private static let goSample: String = {
        var text = "package sample\n\n"
        var index = 0
        while text.utf8.count < 50_000 {
            text += "// Add\(index) adds \(index).\nfunc Add\(index)(a int) int {\n\treturn a + \(index)\n}\n\n"
            index += 1
        }
        return text
    }()

    private static func request(_ text: String, language: Language) -> TierRequest {
        var lines: [Range<Int>] = []
        var start = 0
        for (offset, byte) in text.utf8.enumerated() where byte == UInt8(ascii: "\n") {
            lines.append(start ..< offset)
            start = offset + 1
        }
        lines.append(start ..< text.utf8.count)
        return TierRequest(
            revision: SourceRevision(documentID: "sample", language: language, key: .content(UUID().uuidString)),
            text: text, lineRanges: lines, visibleLines: 0 ..< min(60, lines.count))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["GDV_BENCH"] != nil))
    func `the JSON and Python samples parse within the deadline`() async throws {
        let corpus = try GrammarCorpus.bundled()
        let cache = FileManager.default.temporaryDirectory.appending(path: "atelier-bench-grammar-tables")
        let artifacts = SyntaxArtifactsCache(
            registry: GrammarRegistry(cacheDirectory: cache, bundledManifest: try corpus.manifest()),
            grammarsDirectory: corpus.grammarsDirectory)
        let json = try String(
            contentsOf: corpus.grammarsDirectory.appending(path: "python/grammar.json"), encoding: .utf8)
        let python = try String(
            contentsOf: Self.repository.appending(path: "Apps/GitDiffViewer/scripts/main_actor_budget.py"),
            encoding: .utf8)

        for (language, text) in [(Language.json, json), (.python, python)] {
            let record = GrammarTierRecord()
            let tier = GrammarTier(artifacts: artifacts, record: record)
            try await tier.run(Self.request(text, language: language), emit: { _ in })
            let grammar = try #require(artifacts.artifacts(for: language.name)?.grammarKey)
            let took = try #require(record.predictedDuration(grammar: grammar, bytes: text.utf8.count))
            print("GrammarTierDeadlineBenchmark: \(language.name), \(text.utf8.count) bytes, \(took) of CPU")
            #expect(took <= GrammarTier.defaultDeadline)
        }

        let record = GrammarTierRecord()
        let outcome: String
        do {
            let tier = GrammarTier(artifacts: artifacts, record: record)
            try await tier.run(Self.request(Self.goSample, language: .go), emit: { _ in })
            let grammar = try #require(artifacts.artifacts(for: "go")?.grammarKey)
            outcome = String(describing: record.predictedDuration(grammar: grammar, bytes: Self.goSample.utf8.count))
        } catch {
            outcome = String(describing: error)
        }
        print("GrammarTierDeadlineBenchmark: go, \(Self.goSample.utf8.count) bytes, \(outcome)")
    }
}

import AtelierLexers
import AtelierSyntaxModel
import Foundation
import Testing

@testable import KittySyntax

/// Opt-in timing of the full-document lexical pass on a million-line Swift file, in a release build: the scan as
/// `LanguageHighlighter.Session` runs it for its lexical layer, then the whole `highlightDocument` of a session
/// without a grammar, which Swift always is.
///
/// `GDV_BENCH=1 swift test -c release --filter LexicalScanBenchmark`. `GDV_BENCH_SOURCE` names a Swift file whose
/// lines repeat to a million; without it generated lines stand in. The checksum covers every token of the scan, so
/// two builds that print the same checksum produce the same tokens.
struct LexicalScanBenchmark {
    private static let lineCount = 1_000_000

    @Test(.enabled(if: ProcessInfo.processInfo.environment["GDV_BENCH"] != nil))
    func `scans and highlights a million line swift document`() throws {
        let source = try Self.document()
        try #require(!source.isEmpty)
        var scans: [Double] = []
        var tokenCount = 0
        var checksum: UInt64 = 0
        for iteration in 0 ..< 13 {
            // Each result is released before the next timed call, so no call pays for freeing another's.
            var tokens: [HighlightToken] = []
            let scan = Self.milliseconds {
                tokens = LexicalHighlightEngine().highlight(utf8: Array(source.utf8), language: .swift)
            }
            if iteration == 0 {
                tokenCount = tokens.count
                checksum = Self.checksum(of: tokens)
            } else if iteration >= 2 {
                scans.append(scan)
            }
        }
        let session = LanguageHighlighter.makeSession(language: "swift", theme: .monokai, preferGrammar: false)
        var documents: [Double] = []
        for iteration in 0 ..< 5 {
            var lines: [[StyledSpan]] = []
            let document = Self.milliseconds { lines = session.highlightDocument(source: source) }
            #expect(lines.count == Self.lineCount + 1)
            if iteration >= 1 { documents.append(document) }
        }
        print("BENCH kitty-document bytes \(source.utf8.count) tokens \(tokenCount) checksum \(checksum)")
        for (name, samples) in [("scan", scans), ("highlightDocument", documents)] {
            let sorted = samples.sorted()
            let rounded = sorted.map { ($0 * 1_000).rounded() / 1_000 }
            print("BENCH kitty-document \(name) median \(sorted[sorted.count / 2]) ms samples \(rounded)")
        }
    }

    /// A million lines: `GDV_BENCH_SOURCE`'s lines in a loop, or generated ones.
    private static func document() throws -> String {
        let seed: String
        if let path = ProcessInfo.processInfo.environment["GDV_BENCH_SOURCE"] {
            seed = String(decoding: try Data(contentsOf: URL(fileURLWithPath: path)), as: UTF8.self)
        } else {
            seed = (0 ..< 1_000)
                .map { index in
                    "    let value\(index) = compute(index: \(index), name: \"item \(index) ✓\") // trailing note\n"
                        + "    /* block */ @MainActor func f\(index)() async throws -> Int { 0x1F + 1.5e3 }\n"
                }
                .joined()
        }
        var lines = seed.split(separator: "\n", omittingEmptySubsequences: false)
        if lines.last?.isEmpty == true { lines.removeLast() }
        guard !lines.isEmpty else { return "" }
        var document = ""
        document.reserveCapacity(seed.utf8.count * (Self.lineCount / lines.count + 1))
        for index in 0 ..< Self.lineCount {
            document += lines[index % lines.count]
            document += "\n"
        }
        return document
    }

    /// FNV-1a over each token's role and byte range.
    private static func checksum(of tokens: [HighlightToken]) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for token in tokens {
            let fields = [
                UInt64(token.role.rawValue), UInt64(token.byteRange.lowerBound), UInt64(token.byteRange.upperBound)
            ]
            for field in fields { hash = (hash ^ field) &* 1_099_511_628_211 }
        }
        return hash
    }

    private static func milliseconds(_ body: () -> Void) -> Double {
        let elapsed = ContinuousClock().measure(body)
        return Double(elapsed.components.seconds) * 1_000 + Double(elapsed.components.attoseconds) / 1e15
    }
}

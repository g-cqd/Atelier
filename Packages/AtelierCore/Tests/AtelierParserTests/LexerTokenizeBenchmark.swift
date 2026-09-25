import Foundation
import Testing

@testable import AtelierGrammar
@testable import AtelierParser

/// Opt-in timing of the context-free ``Lexer`` over JavaScript: its keyword trie and comment patterns, from
/// KittyCode's JavaScript grammar, on about 270 KB of code with keywords, identifiers, strings and comments.
///
/// Set `GDV_BENCH`; `GDV_BENCH_RUNS` sets the timed runs (11 by default), after one untimed run. The checksum covers
/// every token's type and ranges, so two builds that print the same checksum produce the same tokens.
struct LexerTokenizeBenchmark {
    private static let environment = ProcessInfo.processInfo.environment

    @Test(.enabled(if: environment["GDV_BENCH"] != nil))
    func `tokenizes JavaScript with the context-free lexer`() throws {
        let grammarURL = BundledGrammarFixture.grammarURL(language: "javascript")
        let grammar = try GrammarLoader.parse(Data(contentsOf: grammarURL))
        let lexer = Lexer(lexTable: LexTableCompiler.compile(grammar))
        let source = Self.document()
        let runs = max(Int(Self.environment["GDV_BENCH_RUNS"] ?? "") ?? 11, 1)
        let clock = ContinuousClock()
        let tokens = lexer.tokenize(source)
        var samples: [Double] = []
        for _ in 0 ..< runs {
            let start = clock.now
            _ = lexer.tokenize(source)
            let (seconds, attoseconds) = start.duration(to: clock.now).components
            samples.append(Double(seconds) * 1_000 + Double(attoseconds) / 1e15)
        }
        samples.sort()
        func rank(_ fraction: Double) -> Double {
            samples[min(samples.count - 1, Int((Double(samples.count - 1) * fraction).rounded()))]
        }
        print(
            "LEXER BENCH \(source.utf8.count) bytes, \(tokens.count) tokens, checksum \(Self.checksum(of: tokens)): "
                + String(
                    format: "median %.3f ms, p10 %.3f ms, p90 %.3f ms over %d runs", rank(0.5), rank(0.1), rank(0.9),
                    runs))
        #expect(tokens.last?.byteRange.upperBound == source.utf8.count)
    }

    /// About 270 KB of JavaScript.
    private static func document() -> String {
        (0 ..< 1_024)
            .map { index in
                """
                // Returns the value of item \(index), clamped to the table.
                export async function compute\(index)(index, name) {
                  /* scratch \(index) */ const value = index * \(index % 97) + name.length;
                  if (value > 0 && typeof name === "string") { return await label(`item ${index}`); }
                  return null;
                }

                """
            }
            .joined()
    }

    /// FNV-1a over each token's type and byte range.
    private static func checksum(of tokens: [Lexer.Token]) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        func mix(_ value: Int) {
            hash = (hash ^ UInt64(bitPattern: Int64(value))) &* 0x0000_0100_0000_01b3
        }
        for token in tokens {
            for byte in token.type.utf8 { mix(Int(byte)) }
            mix(token.byteRange.lowerBound)
            mix(token.byteRange.upperBound)
            mix(token.pointRange.upperBound.row)
            mix(token.pointRange.upperBound.column)
            mix(token.isExtra ? 1 : 0)
        }
        return hash
    }
}

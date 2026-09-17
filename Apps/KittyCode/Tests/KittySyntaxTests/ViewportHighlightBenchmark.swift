import AtelierSyntaxModel
import Foundation
import Testing

@testable import KittySyntax

/// Opt-in timing of the paths a keystroke exercises on a large file: `ATELIER_BENCH=1 swift test --filter ViewportHighlightBenchmark`.
struct ViewportHighlightBenchmark {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ATELIER_BENCH"] != nil))
    func `viewport and document highlighting on a 20k-line swift file`() {
        var lines: [String] = []
        for index in 0 ..< 20_000 {
            lines.append("    let value\(index) = compute(index: \(index), name: \"item \(index)\") // trailing note")
        }
        let source = lines.joined(separator: "\n")
        let session = LanguageHighlighter.makeSession(language: "swift", theme: .monokai, preferGrammar: false)
        let clock = ContinuousClock()
        var viewportTime = Duration.zero
        for scroll in 0 ..< 50 {
            let start = scroll * 300
            viewportTime += clock.measure {
                _ = session.highlightViewport(source: source, visibleLineRange: start ..< start + 60)
            }
        }
        let documentTime = clock.measure { _ = session.highlightDocument(source: source) }
        let linesTime = clock.measure { _ = session.highlightLines(lines[0 ..< 60]) }
        print("BENCH viewport highlight (60 of 20k lines): \(viewportTime / 50) per call")
        print("BENCH document highlight (20k lines): \(documentTime)")
        print("BENCH highlightLines (60 lines): \(linesTime)")
    }
}

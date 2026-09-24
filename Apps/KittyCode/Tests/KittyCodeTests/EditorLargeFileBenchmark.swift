import AtelierText
import Foundation
import KittyStyle
import KittySyntax
import KittyWorkspace
import Testing

import func AemiTestKit.mallocDelta

@testable import KittyEditor

/// Release timings of the editor's main-actor work on a million-line Swift-like file, printed rather than asserted:
/// `GDV_BENCH=1 swift test -c release --filter EditorLargeFileBenchmark`. The one assertion counts allocations, and the
/// counter is process-wide, so run the suite alone.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["GDV_BENCH"] != nil))
@MainActor
struct EditorLargeFileBenchmark {
    private static let lineCount = 1_000_000
    private static let lines: [String] = (0 ..< lineCount).map(swiftLikeLine)
    private static let text = lines.joined(separator: "\n")

    /// Doc comments, declarations, strings, a block comment and a blank line, cycling so every run reads the same text.
    nonisolated private static func swiftLikeLine(_ index: Int) -> String {
        switch index % 8 {
            case 0: "/// Returns the value for item \(index), clamped to the table."
            case 1: "public func compute\(index)(index: Int, name: String) -> Int {"
            case 2: "    let value = index &* \(index % 97) + name.utf8.count  // trailing note"
            case 3: "    guard value > 0 else { return 0 }"
            case 4: "    /* scratch \(index) */ let label = \"item \\(index) of \(index)\""
            case 5: "    return value + label.count"
            case 6: "}"
            default: ""
        }
    }

    private static func summary(_ samples: [Duration]) -> String {
        let milliseconds =
            samples.map {
                Double($0.components.seconds) * 1_000 + Double($0.components.attoseconds) / 1e15
            }
            .sorted()
        return String(
            format: "median %.4f ms, p10 %.4f, p90 %.4f, n %d", milliseconds[milliseconds.count / 2],
            milliseconds[milliseconds.count / 10], milliseconds[milliseconds.count * 9 / 10], milliseconds.count)
    }

    /// The document open in a buffer, fully highlighted and measured, with the cursor and a 60-row screen halfway down.
    private func makeHighlightedState() -> EditorState {
        let state = EditorState(rootPath: ".", config: KittyConfig())
        state.bufferManager.open(
            filePath: "/bench/large.swift", fileName: "large.swift", content: Self.text, language: "swift")
        state.restoreStateFromActiveBuffer()
        state.lastRenderRows = 60
        state.cursorRow = 500_000
        state.cursorCol = 4
        state.scrollOffset = 499_980
        let session = LanguageHighlighter.makeSession(language: "swift", theme: state.syntaxTheme, preferGrammar: false)
        state.highlightedLines = session.highlightLines(Self.lines)
        state.cachedMaxLineWidth = TextDocument.computeMaxLineWidth(for: Self.lines)
        return state
    }

    @Test func `a keystroke in the middle of a million-line file`() {
        let state = makeHighlightedState()
        defer { state.shutdown() }
        for _ in 0 ..< 5 { insertText("x", into: state) }
        let clock = ContinuousClock()
        let samples = (0 ..< 31).map { _ in clock.measure { insertText("x", into: state) } }
        let edited = [StyledSpan(text: "edited", style: .default)]
        state.highlightedLines.replaceSubrange(10 ..< 11, with: [edited])
        let allocations = mallocDelta { state.highlightedLines.replaceSubrange(10 ..< 11, with: [edited]) }
        print(
            "BENCH keystroke, 1M lines: \(Self.summary(samples)); one replaceSubrange through the state: "
                + "\(allocations.map { "\($0) allocations" } ?? "not counted")")
        if let allocations { #expect(allocations == 0) }
    }
}

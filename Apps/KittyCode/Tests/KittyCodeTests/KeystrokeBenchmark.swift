import AtelierText
import Foundation
import KittyCodecs
import KittyFileTree
import KittyGit
import KittyRenderer
import KittySyntax
import KittyTerminal
import KittyWidgets
import KittyWorkspace
import Testing

@testable import KittyEditor

/// Opt-in timing of one keystroke and one render on a large file: `ATELIER_BENCH=1 swift test --filter KeystrokeBenchmark`.
@Suite
@MainActor
struct KeystrokeBenchmark {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ATELIER_BENCH"] != nil))
    func `typing into a 20k-line swift file`() {
        var lines: [String] = []
        for index in 0 ..< 20_000 {
            lines.append("    let value\(index) = compute(index: \(index), name: \"item \(index)\") // trailing note")
        }
        let sut = EditorTestHarness.make(fileContent: lines, columns: 120, rows: 50)
        sut.state.currentLanguage = "swift"
        sut.state.cursorRow = 10_000
        sut.state.scrollOffset = 9_980
        let clock = ContinuousClock()
        let open = clock.measure { sut.state.refreshHighlights() }
        var typing = Duration.zero
        for index in 0 ..< 100 {
            let one = clock.measure { insertText("x", into: sut.state) }
            if index < 6 || index % 25 == 0 { print("BENCH keystroke #\(index): \(one)") }
            typing += one
        }
        var rendering = Duration.zero
        for _ in 0 ..< 20 {
            rendering += clock.measure {
                sut.pipeline.beginFrame()
                renderShellLayout(pipeline: sut.pipeline, state: sut.state)
            }
        }
        insertText("y", into: sut.state)
        let materialise = clock.measure { _ = sut.state.fileContent }
        let lineSlice = clock.measure { _ = sut.state.textBuffer.lines(in: 9_980 ..< 10_040) }
        let session = LanguageHighlighter.makeSession(language: "swift", theme: .monokai, preferGrammar: false)
        let window = clock.measure { _ = session.highlightLines(lines[9_980 ..< 10_040]) }
        var ropeInsert = Duration.zero
        var snapshotTime = Duration.zero
        var historyTime = Duration.zero
        var didChange = Duration.zero
        for _ in 0 ..< 20 {
            snapshotTime += clock.measure { _ = sut.state.activeBufferSnapshot() }
            let before = sut.state.activeBufferSnapshot()
            var mutation: TextMutation?
            ropeInsert += clock.measure {
                mutation = TextOperations.insert("z", into: &sut.state.textBuffer, at: &sut.state.textCursor)
            }
            let after = sut.state.activeBufferSnapshot()
            if let before, let after, let buffer = sut.state.bufferManager.activeBuffer {
                historyTime += clock.measure {
                    buffer.editHistory.recordChange(from: before, to: after, coalescingWindow: nil)
                }
            }
            if let mutation {
                didChange += clock.measure { sut.state.textDidChange(mutation, previousSnapshot: nil) }
            }
        }
        var withHistory = Duration.zero
        for _ in 0 ..< 5 {
            let before = sut.state.activeBufferSnapshot()
            let mutation = TextOperations.insert("w", into: &sut.state.textBuffer, at: &sut.state.textCursor)
            withHistory += clock.measure { sut.state.textDidChange(mutation, previousSnapshot: before) }
        }
        print("BENCH textDidChange with history: \(withHistory / 5)")
        print(
            "BENCH rope insert: \(ropeInsert / 20)  snapshot: \(snapshotTime / 20)  history record: \(historyTime / 20)  textDidChange(no history): \(didChange / 20)"
        )
        print("BENCH fileContent materialisation after an edit: \(materialise)")
        print("BENCH 60-line slice from the buffer: \(lineSlice)")
        print("BENCH highlightLines 60 lines: \(window)")
        print("BENCH open highlight (20k lines): \(open)")
        print("BENCH keystroke: \(typing / 100) per keystroke")
        print("BENCH render frame: \(rendering / 20) per frame")
    }
}

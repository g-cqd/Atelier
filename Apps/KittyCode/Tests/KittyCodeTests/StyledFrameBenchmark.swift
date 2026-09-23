import Foundation
import KittyRenderer
import Testing

@testable import KittyEditor

/// Opt-in timing of the full frame path with the same long-line viewport as the renderer benchmark.
@Suite
@MainActor
struct StyledFrameBenchmark {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GDV_BENCH"] != nil))
    func `render two hundred long lines through the frame pipeline`() {
        let line = String(repeating: "abcdefghijklmnopqrstuvwxyz0123456789", count: 569)
        let sut = EditorTestHarness.make(
            fileContent: Array(repeating: line, count: 200),
            columns: 80,
            rows: 201,
            statusBar: false,
            sidebarCollapsed: true
        )
        let clock = ContinuousClock()
        sut.state.markEverythingDirty()
        renderFrame(pipeline: sut.pipeline, state: sut.state)

        var samples: [Duration] = []
        samples.reserveCapacity(7)
        for _ in 0 ..< 7 {
            sut.state.markEverythingDirty()
            samples.append(
                clock.measure {
                    renderFrame(pipeline: sut.pipeline, state: sut.state)
                })
        }
        samples.sort()
        print("BENCH full styled frame median: \(samples[3]); samples: \(samples)")
        let lastContentRow = String((0 ..< 80).map { sut.pipeline.buffer[198, $0].character })
        #expect(lastContentRow.contains("abc"))
    }
}

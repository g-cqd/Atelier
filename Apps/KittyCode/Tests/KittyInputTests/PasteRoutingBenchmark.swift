import Foundation
import Testing

@testable import KittyCodecs
@testable import KittyInput

/// Release timing of routing a bracketed paste just under the cap, printed rather than asserted:
/// `GDV_BENCH=1 swift test -c release --filter PasteRoutingBenchmark`. The bytes arrive in 4 KiB reads, as the terminal
/// hands them to the router.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["GDV_BENCH"] != nil))
struct PasteRoutingBenchmark {
    @Test func `routing a paste of a mebibyte in 4 KiB reads`() {
        let line = Array("    let value = compute(index: 42, name: \"item\") // a pasted line\n".utf8)
        var body: [UInt8] = []
        while body.count + line.count <= SequenceRouter.maxPasteSize - 64 { body += line }
        let input = Array("\u{1B}[200~".utf8) + body + Array("\u{1B}[201~".utf8)
        let clock = ContinuousClock()
        var router = SequenceRouter()
        var events: [InputEvent] = []
        var samples: [Duration] = []
        for run in 0 ..< 36 {
            var pastes = 0
            let elapsed = clock.measure {
                input.withUnsafeBytes { bytes in
                    var start = 0
                    while start < bytes.count {
                        let end = min(bytes.count, start + 4_096)
                        router.feedAll(UnsafeRawBufferPointer(rebasing: bytes[start ..< end]), into: &events)
                        pastes += events.count { if case .paste = $0 { true } else { false } }
                        start = end
                    }
                }
            }
            #expect(pastes == 1)
            // Five warm-up runs.
            if run >= 5 { samples.append(elapsed) }
        }
        let milliseconds =
            samples.map { Double($0.components.attoseconds) / 1e15 + Double($0.components.seconds) * 1e3 }
            .sorted()
        print(
            String(
                format: "BENCH paste routing, 1 MiB in 4 KiB reads: median %.3f ms, p10 %.3f, p90 %.3f, n %d",
                milliseconds[milliseconds.count / 2], milliseconds[milliseconds.count / 10],
                milliseconds[milliseconds.count * 9 / 10], milliseconds.count))
    }
}

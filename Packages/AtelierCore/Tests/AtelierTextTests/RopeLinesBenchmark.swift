import Foundation
import Testing

@testable import AtelierText

/// `Rope.lines(in:)` against the ranged read it replaced, which copied the range into one `Data` and split it through
/// `Data`'s per-byte subscript. Both run interleaved on the same cold rope, whose lines cache stays empty.
///
/// Run in release, alone on the machine: `GDV_BENCH=1 swift test -c release -Xswiftc -enable-testing --filter
/// RopeLinesBenchmark`.
@Suite struct RopeLinesBenchmark {
    /// One million lines of code-like text, some indented, some blank, one in sixteen long.
    private static let rope: Rope = {
        let arguments = String(repeating: "argument, ", count: 12)
        var text = ""
        text.reserveCapacity(48_000_000)
        for index in 0 ..< 1_000_000 {
            switch index % 16 {
                case 0: text += "\n"
                case 7: text += "        let value\(index) = compute(\(index), \(arguments))\n"
                default: text += "    let value\(index) = compute(\(index)) // text\n"
            }
        }
        var rope = Rope(text)
        rope.invalidateSnapshotCaches()
        return rope
    }()

    @Test(.enabled(if: ProcessInfo.processInfo.environment["GDV_BENCH"] != nil))
    func `a viewport of 60 lines from a million`() {
        let rope = Self.rope
        let starts = (0 ..< 200).map { ($0 * 4_999) % (rope.lineCount - 60) }
        compare("60 lines x 200 reads", unit: "us") { read in
            var sink = 0
            for start in starts { sink &+= read(rope, start ..< start + 60).count }
            return sink
        }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["GDV_BENCH"] != nil))
    func `a million lines read 4096 at a time`() {
        let rope = Self.rope
        compare("1M lines by 4096", unit: "ms") { read in
            var sink = 0
            for start in stride(from: 0, to: rope.lineCount, by: 4_096) {
                sink &+= read(rope, start ..< min(start + 4_096, rope.lineCount)).count
            }
            return sink
        }
    }

    /// Times `work` with the previous read and the current one, alternating which goes first, 31 rounds each, and
    /// prints the median with p10 and p90.
    private func compare(
        _ name: String, unit: String, _ work: ((Rope, Range<Int>) -> [String]) -> Int
    ) {
        var before: [Double] = []
        var after: [Double] = []
        let scale = unit == "us" ? 1e6 : 1e3
        #expect(work(Self.legacyLines) == work { $0.lines(in: $1) })
        for round in 0 ..< 31 {
            for current in round.isMultiple(of: 2) ? [false, true] : [true, false] {
                let start = ContinuousClock.now
                let sink = current ? work { $0.lines(in: $1) } : work(Self.legacyLines)
                let elapsed = start.duration(to: .now)
                let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
                withExtendedLifetime(sink) {}
                if current { after.append(seconds * scale) } else { before.append(seconds * scale) }
            }
        }
        print("ROPE \(name): before \(Self.summary(before)) \(unit), after \(Self.summary(after)) \(unit)")
    }

    private static func summary(_ samples: [Double]) -> String {
        let sorted = samples.sorted()
        let pick = { (fraction: Double) in sorted[Int((Double(sorted.count - 1) * fraction).rounded())] }
        return String(format: "median %.1f (p10 %.1f, p90 %.1f)", pick(0.5), pick(0.1), pick(0.9))
    }

    /// The previous `lines(in:)`: one ranged byte read, split byte by byte.
    private static func legacyLines(_ rope: Rope, _ range: Range<Int>) -> [String] {
        let clamped = range.clamped(to: 0 ..< rope.lineCount)
        guard !clamped.isEmpty else { return [] }
        let start = rope.lineRange(forLine: clamped.lowerBound).lowerBound
        let end = rope.lineRange(forLine: clamped.upperBound - 1).upperBound
        let data = rope.bytes(in: start ..< end)
        var lines: [String] = []
        lines.reserveCapacity(clamped.count)
        var lineStart = data.startIndex
        for index in data.indices where data[index] == 0x0A {
            lines.append(String(decoding: data[lineStart ..< index], as: UTF8.self))
            lineStart = index + 1
        }
        lines.append(String(decoding: data[lineStart...], as: UTF8.self))
        return lines
    }
}

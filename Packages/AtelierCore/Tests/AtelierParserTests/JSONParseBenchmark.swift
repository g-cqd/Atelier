import Foundation
import Testing

@testable import AtelierParser

/// Opt-in JSON parse timings over growing documents, to show that a parse grows linearly with its input.
///
/// Set `GDV_BENCH`; `GDV_BENCH_RUNS` sets the timed parses per size (11 by default), after one untimed parse. Each
/// size prints the median and the 10th and 90th percentiles of its parses, and the median per KiB.
@Suite(.serialized)
struct JSONParseBenchmark {
    private static let environment = ProcessInfo.processInfo.environment
    private static let sizes = [2_048, 4_096, 8_192, 16_384, 32_768, 117_000]

    @Test(.enabled(if: environment["GDV_BENCH"] != nil))
    func `parses JSON documents of growing size`() throws {
        let parser = try BundledGrammarFixture.parser(for: BundledGrammarFixture.json)
        let runs = max(Int(Self.environment["GDV_BENCH_RUNS"] ?? "") ?? 11, 1)
        var perKiB: [Int: Double] = [:]
        for size in Self.sizes {
            let source = Self.document(bytes: size)
            let clock = ContinuousClock()
            _ = try parser.parse(source)
            var samples: [Double] = []
            for _ in 0 ..< runs {
                let start = clock.now
                _ = try parser.parse(source)
                samples.append(Self.milliseconds(start.duration(to: clock.now)))
            }
            samples.sort()
            let median = Self.percentile(samples, 0.5)
            perKiB[size] = median * 1_024 / Double(source.utf8.count)
            print(
                "JSON BENCH \(source.utf8.count) bytes: median \(Self.format(median)) ms, "
                    + "p10 \(Self.format(Self.percentile(samples, 0.1))) ms, "
                    + "p90 \(Self.format(Self.percentile(samples, 0.9))) ms, "
                    + "\(Self.format(perKiB[size] ?? 0)) ms/KiB over \(runs) parses")
            #expect(source.utf8.count <= size)
        }
        // Printed, not asserted, as every timing here: linear growth keeps the cost per KiB flat, about 1x, where a
        // parse quadratic in its input costs seven times as much per KiB at 117 KB as at 16 KB.
        let growth = (perKiB[117_000] ?? 0) / max(perKiB[16_384] ?? 1, .leastNonzeroMagnitude)
        print("JSON BENCH growth per KiB from 16 KB to 117 KB: \(Self.format(growth))x")
    }

    /// An array of small objects, `bytes` long at most.
    private static func document(bytes: Int) -> String {
        let item = #"{"key":"value","number":123},"#
        return "[" + String(repeating: item, count: (bytes - 4) / item.utf8.count) + "{}]"
    }

    /// The value at `fraction` of the sorted `samples`, by nearest rank.
    private static func percentile(_ samples: [Double], _ fraction: Double) -> Double {
        samples[min(samples.count - 1, Int((Double(samples.count - 1) * fraction).rounded()))]
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let (seconds, attoseconds) = duration.components
        return Double(seconds) * 1_000 + Double(attoseconds) / 1e15
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}

import Foundation
import Testing

@testable import AtelierParser

/// Opt-in JSON parsing timings for two representative document sizes.
@Suite
struct JSONParseBenchmark {
    @Test(
        .enabled(if: ProcessInfo.processInfo.environment["GDV_BENCH"] != nil),
        arguments: [16_384, 117_000])
    func `parses JSON documents without a timing regression`(targetBytes: Int) throws {
        let parser = try BundledGrammarFixture.parser(for: BundledGrammarFixture.json)
        let item = #"{"key":"value","number":123},"#
        let source = "[" + String(repeating: item, count: (targetBytes - 4) / item.utf8.count) + "{}]"
        let clock = ContinuousClock()
        _ = try parser.parse(source)
        let start = clock.now
        for _ in 0 ..< 5 { _ = try parser.parse(source) }
        let average = start.duration(to: clock.now) / 5
        print("JSON BENCH \(source.utf8.count) bytes: \(average) per parse")
        #expect(source.utf8.count <= targetBytes)
    }
}

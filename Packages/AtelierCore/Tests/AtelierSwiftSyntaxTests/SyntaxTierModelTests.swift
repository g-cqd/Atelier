import AtelierDiff
import AtelierSyntaxModel
import Foundation
import Synchronization
import Testing

@testable import AtelierSwiftSyntax

struct SyntaxTierModelTests {
    @Test
    func `paired line emphasis matches whole side tokenization`() throws {
        let old = "let greeting = \"hello world\"\n/* café 😀 open\n   middle old */\nlet tail = 1\n"
        let new = "let greeting = \"hello there\"\n/* café 😀 open\n   middle new */\nlet tail = 2\n"
        let provider = SwiftSyntaxTokenRanges()
        let oldTokens = provider.tokenRangesByLine(text: old, language: .swift)
        let newTokens = provider.tokenRangesByLine(text: new, language: .swift)
        let pipeline = DiffPipeline()
        let model = DiffModel(
            oldText: old, newText: new, granularity: .syntax, language: .swift, pipeline: pipeline,
            tokenRanges: provider)

        let modified = model.splitRows.filter { $0.kind == .modified }
        #expect(!modified.isEmpty)
        for row in modified {
            let oldRef = try #require(row.old)
            let newRef = try #require(row.new)
            let expected = IntralineDiff.emphasis(
                old: model.oldLines[oldRef.index], new: model.newLines[newRef.index], granularity: .syntax,
                oldTokens: oldTokens[oldRef.index], newTokens: newTokens[newRef.index],
                refiners: pipeline.intralineRefiners)
            #expect(oldRef.emphasis == (expected?.old ?? []))
            #expect(newRef.emphasis == (expected?.new ?? []))
            let oldUnified = model.unifiedRows.first { $0.kind == .removed && $0.old?.index == oldRef.index }
            let newUnified = model.unifiedRows.first { $0.kind == .added && $0.new?.index == newRef.index }
            #expect(oldUnified?.old?.emphasis == (expected?.old ?? []))
            #expect(newUnified?.new?.emphasis == (expected?.new ?? []))
        }
    }

    @Test
    func `added lines do not request syntax tokens`() {
        let spy = TokenRangeSpy()
        let text = Array(repeating: "let number = 1", count: 2_374).joined(separator: "\n")
        let model = DiffModel(oldText: "", newText: text, granularity: .syntax, language: .swift, tokenRanges: spy)
        #expect(model.newLines.count == 2_374)
        #expect(spy.calls.withLock { $0 }.isEmpty)
    }

    @Test
    func `multiple changed hunks request paired lines once per side`() {
        let spy = SelectedTokenRangeSpy()
        let model = DiffModel(
            oldText: "let first = 1\nshared\nlet second = 2\n",
            newText: "let first = 3\nshared\nlet second = 4\n",
            granularity: .syntax, language: .swift, tokenRanges: spy)
        #expect(model.splitRows.filter { $0.kind == .modified }.count == 2)
        #expect(spy.requests.withLock { $0 } == [[0, 2], [0, 2]])
    }

    @Test
    func `selected Swift lines have the same token ranges as whole side tokenization`() {
        let text = "let a = \"😀\"\r\n/* café open\n\n  middle words */\nlet z = 2\n"
        let provider = SwiftSyntaxTokenRanges()
        let whole = provider.tokenRangesByLine(text: text, language: .swift)
        let indices = [0, 2, 3, 4]
        let selected = provider.tokenRangesByLine(text: text, language: .swift, lineIndices: indices)
        #expect(selected.count == indices.count)
        for index in indices {
            #expect(selected[index] == whole[index])
        }
    }

    @Test
    func `selected non Swift lines have the same token ranges as whole side tokenization`() {
        let text = "@interface Thing\n@\"hello world\"\n@end"
        let provider = SwiftSyntaxTokenRanges()
        let whole = provider.tokenRangesByLine(text: text, language: .objectiveC)
        let selected = provider.tokenRangesByLine(text: text, language: .objectiveC, lineIndices: [1])
        #expect(selected == [1: whole[1]])
    }
}

private final class TokenRangeSpy: SyntaxTokenRanging {
    let calls = Mutex<[Int]>([])

    func tokenRangesByLine(text: String, language: Language) -> [[Range<Int>]] {
        calls.withLock { $0.append(text.utf8.count) }
        return CodeTokenRanges().tokenRangesByLine(text: text, language: language)
    }
}

private final class SelectedTokenRangeSpy: SelectedSyntaxTokenRanging {
    let requests = Mutex<[[Int]]>([])

    func tokenRangesByLine(text: String, language: Language) -> [[Range<Int>]] {
        requests.withLock { $0.append([]) }
        return CodeTokenRanges().tokenRangesByLine(text: text, language: language)
    }

    func tokenRangesByLine(text: String, language: Language, lineIndices: [Int]) -> [Int: [Range<Int>]] {
        requests.withLock { $0.append(lineIndices) }
        let whole = CodeTokenRanges().tokenRangesByLine(text: text, language: language)
        var selected: [Int: [Range<Int>]] = [:]
        for index in lineIndices { selected[index] = whole[index] }
        return selected
    }
}

struct SyntaxTierBenchmark {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GDV_BENCH"] != nil))
    func `syntax model and comment offset scaling`() {
        let provider = SwiftSyntaxTokenRanges()
        let added = Array(repeating: "let value = 12345 // sample", count: 2_374).joined(separator: "\n")
        let clock = ContinuousClock()
        var wordTimes: [Double] = []
        var syntaxTimes: [Double] = []
        for iteration in 0 ..< 9 {
            let tiers: [IntralineGranularity] = iteration.isMultiple(of: 2) ? [.word, .syntax] : [.syntax, .word]
            for tier in tiers {
                let start = clock.now
                let model = DiffModel(
                    oldText: "", newText: added, granularity: tier, language: .swift, tokenRanges: provider)
                let elapsed = Self.milliseconds(clock.now - start)
                #expect(model.newLines.count == 2_374)
                if tier == .word { wordTimes.append(elapsed) } else { syntaxTimes.append(elapsed) }
            }
        }
        print("BENCH added L word median \(Self.median(wordTimes)) ms; syntax median \(Self.median(syntaxTimes)) ms")

        for words in [500, 1_000, 2_000, 8_000, 16_000] {
            let comment = "// " + Array(repeating: "word", count: words).joined(separator: " ")
            var times: [Double] = []
            for _ in 0 ..< 5 {
                let start = clock.now
                let ranges = provider.tokenRangesByLine(text: comment, language: .swift)
                times.append(Self.milliseconds(clock.now - start))
                #expect(ranges.count == 1)
            }
            print("BENCH comment \(words) words median \(Self.median(times)) ms")
        }

        for words in [500, 2_000, 8_000] {
            let comment = "// " + String(repeating: "café😀 ", count: words)
            var times: [Double] = []
            for _ in 0 ..< 5 {
                let start = clock.now
                let ranges = provider.tokenRangesByLine(text: comment, language: .swift)
                #expect(ranges.count == 1)
                times.append(Self.milliseconds(clock.now - start))
            }
            print("BENCH Unicode comment \(words) words median \(Self.median(times)) ms")
        }
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }

    private static func median(_ values: [Double]) -> Double {
        values.sorted()[values.count / 2]
    }
}

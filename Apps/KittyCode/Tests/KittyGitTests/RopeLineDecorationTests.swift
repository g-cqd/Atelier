import AtelierDiff
import AtelierFileTree
import AtelierProcess
import AtelierTestSupport
import Foundation
import Testing

@testable import AtelierText
@testable import KittyGit

@Suite struct RopeLineDecorationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GDV_BENCH"] != nil))
    func `chunked rope line source benchmark`() throws {
        let rope = Rope(String(repeating: "a line with content\n", count: 100_000))
        let old = LegacyRopeLineSource(rope: rope)
        let new = try #require(RopeLineSource(rope: rope))
        #expect(totalBytes(in: old) == totalBytes(in: new))

        var before: [Double] = []
        var after: [Double] = []
        var sink = 0
        for round in 0 ..< 9 {
            for isOld in round.isMultiple(of: 2) ? [true, false] : [false, true] {
                let start = ContinuousClock.now
                if isOld {
                    sink &+= totalBytes(in: old)
                    before.append(milliseconds(start.duration(to: .now)))
                } else {
                    sink &+= RopeLineSource(rope: rope).map { totalBytes(in: $0) } ?? 0
                    after.append(milliseconds(start.duration(to: .now)))
                }
            }
        }
        print("W3 gutter rope scan 100k: before \(before.sorted()[4]) ms after \(after.sorted()[4]) ms, sink \(sink)")
    }

    @Test func `rope line source crosses chunk boundaries without a whole document snapshot`() throws {
        let rope = Rope((0 ..< 9_000).map { "line \($0)" }.joined(separator: "\n"))
        let source = try #require(RopeLineSource(rope: rope))
        #expect(source.lineCount == 9_000)
        #expect(source.line(at: 4_095) == "line 4095")
        #expect(source.line(at: 4_096) == "line 4096")
        #expect(source.line(at: 8_999) == "line 8999")
        #expect(rope._testSnapshotCachesAreEmpty)
    }

    @Test func `rope decorations equal line array decorations`() {
        let old = ["let total = price * count", "unchanged", "last"]
        let current = ["let total = price * quantity", "added", "unchanged", "last"]
        let expected = GitStatusProvider.lineDecorations(base: old, current: current, addedColor: .added)
        let actual = GitStatusProvider.lineDecorations(
            baseLines: old.map { Substring($0) }, currentRope: Rope(current.joined(separator: "\n")),
            addedColor: .added)
        #expect(actual == expected)
    }

    @Test func `invalid UTF8 rope bytes compare as the displayed text`() {
        let rope = Rope(bytes: Data([0xFF]))
        let expected = GitStatusProvider.lineDecorations(
            base: ["�"], current: rope.allLines, addedColor: .added)
        let actual = GitStatusProvider.lineDecorations(
            baseLines: ["�"], currentRope: rope, addedColor: .added)
        #expect(actual == expected)
    }

    @Test func `an untracked rope above thirty thousand lines gets markers`() async {
        let runner = FakeProcessRunner.gated { spec in
            if spec.arguments.contains("--porcelain=v2") {
                return ProcessOutput(
                    terminationStatus: 0, standardOutput: Data("? large.txt\0".utf8), standardError: Data())
            }
            return .success("")
        }
        let provider = GitStatusProvider(rootPath: "/project", runner: runner)
        await provider.refresh()
        let rope = Rope(String(repeating: "a line long enough to exceed the old byte gate\n", count: 31_000))
        let decorations = await provider.lineDecorations(for: "/project/large.txt", rope: rope)
        #expect(decorations.markers.count == rope.lineCount)
    }

    @Test func `repeated status lookups normalize a path once`() {
        let provider = GitStatusProvider(rootPath: "/project", runner: FakeProcessRunner.gated { _ in .success("") })
        for _ in 0 ..< 100 { _ = provider.status(for: "/project/example.txt") }
        #expect(provider._testPathNormalizationCount == 1)
    }
}

private struct LegacyRopeLineSource: DiffSource {
    let rope: Rope
    var lineCount: Int { rope.lineCount }

    func withLineBytes<R>(at index: Int, _ body: (Span<UInt8>) throws -> R) rethrows -> R {
        let line = rope.line(at: index)
        return try body(line.utf8Span.span)
    }
}

private func totalBytes(in source: some DiffSource) -> Int {
    var count = 0
    for index in 0 ..< source.lineCount {
        count += source.withLineBytes(at: index) { $0.count }
    }
    return count
}

private func milliseconds(_ duration: Duration) -> Double {
    let parts = duration.components
    return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1e15
}

import AtelierSyntaxModel
import Foundation
import Testing

@testable import AtelierSwiftSyntax

/// Opt-in measurement behind ``SyntaxFactsStore/defaultByteLimit`` (PERF-11 step 3): the memory the facts of every
/// Swift file of this repository's sources hold, as the allocator reports it, against the store's estimate, and per
/// kilobyte of source.
///
/// `GDV_BENCH=1 swift test --filter SyntaxFactsMemoryBenchmark`. Run it alone: the allocator's figure is the whole
/// process's.
struct SyntaxFactsMemoryBenchmark {
    private static func liveBytes() -> Int {
        var statistics = malloc_statistics_t()
        malloc_zone_statistics(nil, &statistics)
        return statistics.size_in_use
    }

    private static func sources() throws -> [String] {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var texts: [String] = []
        for folder in ["Packages/AtelierCore/Sources", "Apps/GitDiffViewer/Sources", "Apps/KittyCode/Sources"] {
            let directory = root.appending(path: folder)
            guard let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
                continue
            }
            for case let file as URL in files where file.pathExtension == "swift" {
                texts.append(try String(contentsOf: file, encoding: .utf8))
            }
        }
        return texts
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["GDV_BENCH"] != nil))
    func `measures the memory the facts of this repository's Swift files hold`() throws {
        let texts = try Self.sources()
        try #require(!texts.isEmpty)
        let before = Self.liveBytes()
        var kept: [SyntaxFacts] = []
        kept.reserveCapacity(texts.count)
        for text in texts {
            kept.append(try #require(SwiftSyntaxFacts.extract(text)))
        }
        let actual = Self.liveBytes() - before
        let estimated = kept.reduce(0) { $0 + $1.estimatedBytes }
        let source = texts.reduce(0) { $0 + $1.utf8.count }
        let perKilobyte = Double(actual) / (Double(source) / 1024)
        let meanFile = Double(source) / Double(texts.count)
        // The card list's cap: 200 files, both sides of each, at this repository's mean file size.
        let cardList = 400 * meanFile / 1024 * perKilobyte
        print(
            "SyntaxFactsMemoryBenchmark: \(texts.count) files, \(source / 1024) KB of source (mean \(Int(meanFile)) B); "
                + "facts hold \(actual / 1024) KB as the allocator reports, \(estimated / 1024) KB estimated "
                + "(ratio \(Double(actual) / Double(estimated))); \(Int(perKilobyte)) B per KB of source; "
                + "a full card list's 400 sides: \(Int(cardList) >> 20) MB")
        withExtendedLifetime(kept) {}
        #expect(actual > 0)
    }
}

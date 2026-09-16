import AemiTesting
import AemiCore
import Foundation
@testable import DiffComparison
@testable import DiffGit
@testable import DiffRendering
@testable import DiffTextKit
import Testing

/// Opt-in timing of the model against the real loader: loading a repository comparison, then selecting files.
/// Run with GDV_BENCH=1 and GDV_BENCH_REPO=path; GDV_BENCH_LEFT and GDV_BENCH_RIGHT pick the refs.
@MainActor
struct ModelTimelineBenchmark {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GDV_BENCH"] != nil && ProcessInfo.processInfo.environment["GDV_BENCH_REPO"] != nil))
    func `repository comparison and selections`() async throws {
        let environment = ProcessInfo.processInfo.environment
        let repo = URL(filePath: environment["GDV_BENCH_REPO"] ?? ".", directoryHint: .isDirectory)
        let leftRef = environment["GDV_BENCH_LEFT"] ?? "HEAD~1"
        let rightRef = environment["GDV_BENCH_RIGHT"] ?? "HEAD"
        let defaults = UserDefaults(suiteName: "gdv-bench-\(UUID().uuidString)") ?? .standard
        let model = DiffViewerModel(settings: ViewerSettings(defaults: defaults), reader: SourceLoader(), taskProvider: .default)
        let clock = ContinuousClock()

        var start = clock.now
        model.compareGitChanges(in: repo, leftRef: leftRef, rightRef: rightRef)
        var firstCard: Duration?
        while model.isRendering || model.renderedFiles.isEmpty {
            try await Task.sleep(for: .milliseconds(2))
            if firstCard == nil, !model.renderedFiles.isEmpty { firstCard = clock.now - start }
            if clock.now - start > .seconds(20) { break }
        }
        print("BENCH comparison: first card \(Self.ms(firstCard)) ms, all \(model.renderedFiles.count) files \(Self.ms(clock.now - start)) ms")
        try await Task.sleep(for: .milliseconds(300))

        let files = model.combinedFiles
        for path in files.prefix(3) {
            start = clock.now
            model.select(path)
            let synchronous = model.rendered != nil
            while model.isRendering { try await Task.sleep(for: .milliseconds(1)) }
            print("BENCH select \(path.split(separator: "/").last ?? ""): \(Self.ms(clock.now - start)) ms\(synchronous ? " (synchronous)" : "")")
        }
        start = clock.now
        model.select(nil)
        while model.isRendering || model.renderedFiles.count < files.count { try await Task.sleep(for: .milliseconds(1)) }
        print("BENCH back to all files: \(Self.ms(clock.now - start)) ms")
    }

    private static func ms(_ duration: Duration?) -> String {
        guard let duration else { return "–" }
        return String(format: "%.1f", Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15)
    }
}

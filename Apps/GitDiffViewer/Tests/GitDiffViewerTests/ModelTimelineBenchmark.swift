import AemiCore
import AemiRuntime
import AemiTesting
import AtelierProcess
import Foundation
import Observation
import Testing

@testable import DiffComparison
@testable import DiffGit
@testable import DiffRendering
@testable import DiffTextKit

/// Opt-in timing of the model against the real loader: loading a repository comparison, then selecting files.
/// Run with GDV_BENCH=1 and GDV_BENCH_REPO=path; GDV_BENCH_LEFT and GDV_BENCH_RIGHT pick the refs.
///
/// Every wait is event-driven: observation tracking wakes the benchmark when the model's state changes, and the
/// task provider spy settles it when every task the model spawned has finished. No polling, no sleeps.
@MainActor
struct ModelTimelineBenchmark {
    @Test(
        .timeLimit(.minutes(5)),
        .enabled(
            if: ProcessInfo.processInfo.environment["GDV_BENCH"] != nil
                && ProcessInfo.processInfo.environment["GDV_BENCH_REPO"] != nil))
    func `repository comparison and selections`() async throws {
        let environment = ProcessInfo.processInfo.environment
        let repo = URL(filePath: environment["GDV_BENCH_REPO"] ?? ".", directoryHint: .isDirectory)
        let leftRef = environment["GDV_BENCH_LEFT"] ?? "HEAD~1"
        let rightRef = environment["GDV_BENCH_RIGHT"] ?? "HEAD"
        let defaults = UserDefaults(suiteName: "gdv-bench-\(UUID().uuidString)") ?? .standard
        let spy = TaskProviderSpy(label: "benchmark", defaultTimeout: .seconds(120))
        let pool = BlockingOffloadPool(width: 4)
        defer { pool.shutdown() }
        let loader = SourceLoader(runner: HardenedProcessRunner(pool: pool))
        let model = DiffViewerModel(settings: ViewerSettings(defaults: defaults), reader: loader, taskProvider: spy)
        let clock = ContinuousClock()

        var start = clock.now
        model.compareGitChanges(in: repo, leftRef: leftRef, rightRef: rightRef)
        while model.renderedFiles.isEmpty, model.isRendering || model.left.isLoading || model.right.isLoading {
            await Self.nextChange {
                _ = model.renderedFiles
                _ = model.isRendering
                _ = model.left.isLoading
                _ = model.right.isLoading
            }
        }
        try #require(!model.renderedFiles.isEmpty, "\(leftRef) and \(rightRef) compare equal; nothing to time")
        let firstCard = clock.now - start
        try await spy.waitForAllTasks()
        print(
            "BENCH comparison: first card \(Self.ms(firstCard)) ms, all \(model.renderedFiles.count) files \(Self.ms(clock.now - start)) ms"
        )

        let files = model.combinedFiles
        for path in files.prefix(3) {
            start = clock.now
            model.select(path)
            let synchronous = model.rendered != nil
            while model.isRendering {
                await Self.nextChange { _ = model.isRendering }
            }
            print(
                "BENCH select \(path.split(separator: "/").last ?? ""): \(Self.ms(clock.now - start)) ms\(synchronous ? " (synchronous)" : "")"
            )
            try await spy.waitForAllTasks()
        }
        start = clock.now
        model.select(nil)
        while model.isRendering || model.renderedFiles.count < files.count {
            await Self.nextChange {
                _ = model.isRendering
                _ = model.renderedFiles
            }
        }
        print("BENCH back to all files: \(Self.ms(clock.now - start)) ms")
        try await spy.waitForAllTasks()
    }

    /// Suspends until one of the observable properties `read` touches changes.
    private static func nextChange(_ read: @MainActor () -> Void) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            withObservationTracking(read) { continuation.resume() }
        }
    }

    private static func ms(_ duration: Duration?) -> String {
        guard let duration else { return "–" }
        return String(
            format: "%.1f", Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15)
    }
}

import AemiRuntime
import AtelierGit
import AtelierProcess
import Foundation
import Testing

@testable import AtelierSources

/// Opt-in timing of a working-tree reload, over this repository's own checkout unless `GDV_BENCH_ROOT` names another
/// folder; read-only. Run with `GDV_BENCH=1 swift test -c release --filter WorkingTreeReloadBenchmark`.
struct WorkingTreeReloadBenchmark {
    /// The checkout this file lies in: five components up from `Packages/AtelierCore/Tests/AtelierSourcesTests/`.
    private static let checkout = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    @Test(.enabled(if: ProcessInfo.processInfo.environment["GDV_BENCH"] != nil))
    func `a reload of a working tree lists and hashes it again`() async throws {
        let root = ProcessInfo.processInfo.environment["GDV_BENCH_ROOT"].map { URL(filePath: $0) } ?? Self.checkout
        // The app's own shape: one width-4 pool for git runs and file reads.
        let pool = BlockingOffloadPool(width: 4)
        defer { pool.shutdown() }
        let loader = SourceLoader(runner: HardenedProcessRunner(pool: pool), pool: pool)
        let clock = ContinuousClock()

        var entries: [GitTreeEntry] = []
        let first = try await clock.measure { entries = try await loader.entries(of: .directory(root)) }
        var reloads: [Duration] = []
        for _ in 0 ..< 15 {
            reloads.append(try await clock.measure { entries = try await loader.entries(of: .directory(root)) })
        }
        reloads.sort()

        #expect(!entries.isEmpty)
        let bytes = entries.reduce(0) { $0 + $1.size }
        print(
            """
            BENCH working-tree reload of \(entries.count) files (\(bytes) bytes) at \(root.path(percentEncoded: false)): \
            first load \(first), reload median \(reloads[reloads.count / 2]), min \(reloads[0]), \
            max \(reloads[reloads.count - 1])
            """)
    }
}

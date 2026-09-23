import AemiRuntime
import AtelierGit
import AtelierProcess
import Darwin
import Foundation
import Testing

@testable import AtelierSources

/// Opt-in timing of a working-tree reload, over this repository's own checkout unless `GDV_BENCH_ROOT` names another
/// folder; read-only. Run with `GDV_BENCH=1 swift test -c release --filter WorkingTreeReloadBenchmark`.
///
/// Besides wall time it reports CPU time: the loader's own, in this process, and git's, in the child processes it
/// waited for. On a loaded machine wall time mostly measures the wait for a core; CPU time measures the work.
struct WorkingTreeReloadBenchmark {
    /// The checkout this file lies in: five components up from `Packages/AtelierCore/Tests/AtelierSourcesTests/`.
    private static let checkout = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// User and system CPU time used so far by this process, or by the children it has waited for.
    private static func cpuTime(_ who: Int32) -> Duration {
        var usage = rusage()
        getrusage(who, &usage)
        func duration(_ time: timeval) -> Duration { .seconds(time.tv_sec) + .microseconds(time.tv_usec) }
        return duration(usage.ru_utime) + duration(usage.ru_stime)
    }

    private static func median(_ values: [Duration]) -> Duration {
        values.sorted()[values.count / 2]
    }

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
        var walls: [Duration] = []
        var loaderCPU: [Duration] = []
        var gitCPU: [Duration] = []
        for _ in 0 ..< 15 {
            let (selfBefore, childrenBefore) = (Self.cpuTime(RUSAGE_SELF), Self.cpuTime(RUSAGE_CHILDREN))
            walls.append(try await clock.measure { entries = try await loader.entries(of: .directory(root)) })
            loaderCPU.append(Self.cpuTime(RUSAGE_SELF) - selfBefore)
            gitCPU.append(Self.cpuTime(RUSAGE_CHILDREN) - childrenBefore)
        }

        #expect(!entries.isEmpty)
        let bytes = entries.reduce(0) { $0 + $1.size }
        print(
            """
            BENCH working-tree reload of \(entries.count) files (\(bytes) bytes) at \(root.path(percentEncoded: false)): \
            first load \(first), reload median \(Self.median(walls)), min \(walls.min() ?? .zero), \
            max \(walls.max() ?? .zero); median CPU per reload: loader \(Self.median(loaderCPU)), \
            git \(Self.median(gitCPU))
            """)
    }
}

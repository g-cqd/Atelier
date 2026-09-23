import AemiRuntime
import AemiTestKit
import AtelierProcess
import Foundation
import Testing

@testable import AtelierGit

/// Opt-in timing of what the configuration gate adds to one git call; run with GDV_BENCH=1, and GDV_BENCH_REPO to
/// measure a repository of your own instead of a freshly built one.
struct GitConfigGateBenchmark {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GDV_BENCH"] != nil))
    func `the gate costs one git process per configuration change and a few stat calls per call`() async throws {
        let directory = TemporaryDirectory(prefix: "atelier-gate-bench")
        defer { directory.cleanup() }
        let root = try Self.repository(in: directory)
        let pool = BlockingOffloadPool(width: 4)
        defer { pool.shutdown() }
        let runner = HardenedProcessRunner(pool: pool)
        let rounds = 50

        // The gate alone, on a warm cache: the stat calls a cached verdict is checked with.
        let warm = GitConfigGate()
        _ = try await GitClient(repository: root, runner: runner, gate: warm).status()
        let cachedGate = try await Self.median(rounds) {
            _ = try await GitClient.approvedConfiguration(
                in: root, runner: runner, timeout: nil, isolation: .strict, gate: warm)
        }

        // One `git status`, with the verdict cached and with it re-read every time.
        let cachedCall = try await Self.median(rounds) {
            _ = try await GitClient(repository: root, runner: runner, gate: warm).status()
        }
        let uncachedCall = try await Self.median(rounds) {
            _ = try await GitClient(repository: root, runner: runner, gate: GitConfigGate()).status()
        }

        print(
            """
            BENCH git status over \(rounds) rounds at \(root.path(percentEncoded: false)): \
            verdict cached \(cachedCall), verdict re-read \(uncachedCall), gate alone on a hit \(cachedGate)
            """)
    }

    private static func median(_ rounds: Int, _ body: () async throws -> Void) async rethrows -> Duration {
        let clock = ContinuousClock()
        var samples: [Duration] = []
        for _ in 0 ..< rounds {
            samples.append(try await clock.measure { try await body() })
        }
        return samples.sorted()[samples.count / 2]
    }

    /// The repository under measurement: `GDV_BENCH_REPO` when it names one, else a small fresh checkout.
    private static func repository(in directory: TemporaryDirectory) throws -> URL {
        if let path = ProcessInfo.processInfo.environment["GDV_BENCH_REPO"] {
            return URL(filePath: path, directoryHint: .isDirectory)
        }
        let root = URL(filePath: directory.file("repo"), directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        func git(_ arguments: String...) throws {
            let process = Process()
            process.executableURL = GitClient.executable
            process.arguments = ["-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false"] + arguments
            process.currentDirectoryURL = root
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
        }
        try git("init", "-q", "-b", "main")
        for index in 0 ..< 200 {
            try "line \(index)\n".write(to: root.appending(path: "f\(index).txt"), atomically: true, encoding: .utf8)
        }
        try git("add", ".")
        try git("commit", "-q", "-m", "base")
        return root
    }
}

import AemiRuntime
import AtelierProcess
import AtelierTestSupport
import Darwin
import Foundation
import Synchronization

@testable import AtelierSources

/// A pool spy over a real pool of its own: it counts the jobs it is given and notes which threads are inside one of
/// them, so a test tells a call made in a job from one made anywhere else, a cooperative thread included.
final class OffloadSpy: BlockingOffload {
    private struct State {
        var jobs = 0
        var threadsInJobs: Set<UInt64> = []
        /// Runs once, on the pool thread, at the start of the next job, before its body.
        var atNextJobStart: (@Sendable () -> Void)?
    }

    private let pool = BlockingOffloadPool(width: 1)
    private let state = Mutex(State())

    /// How many jobs the spy has been given.
    var jobs: Int { state.withLock(\.jobs) }

    /// Whether the calling thread is running one of this spy's jobs.
    var isInsideJob: Bool {
        let thread = Self.currentThread()
        return state.withLock { $0.threadsInJobs.contains(thread) }
    }

    /// Makes `hook` run on the pool thread at the start of the next job.
    func atNextJobStart(_ hook: @escaping @Sendable () -> Void) {
        state.withLock { $0.atNextJobStart = hook }
    }

    /// Joins the spy's pool thread; call once every job has returned.
    func shutdown() {
        pool.shutdown()
    }

    func run<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        state.withLock { $0.jobs += 1 }
        return try await pool.run {
            let thread = Self.currentThread()
            let hook = self.state.withLock { state in
                state.threadsInJobs.insert(thread)
                defer { state.atNextJobStart = nil }
                return state.atNextJobStart
            }
            defer { _ = self.state.withLock { $0.threadsInJobs.remove(thread) } }
            hook?()
            return try body()
        }
    }

    private static func currentThread() -> UInt64 {
        var thread: UInt64 = 0
        pthread_threadid_np(nil, &thread)
        return thread
    }
}

/// Records every file the loader hashes, and whether the hash ran inside one of `pool`'s jobs, then hashes it as the
/// loader would.
final class HashSpy: Sendable {
    struct Call: Sendable, Equatable {
        let path: String
        let isInsideJob: Bool
    }

    private let pool: OffloadSpy
    private let recorded = Mutex<[Call]>([])

    init(pool: OffloadSpy) {
        self.pool = pool
    }

    var calls: [Call] { recorded.withLock { $0 } }

    /// The paths hashed so far, file names only, in order.
    var names: [String] { calls.map { URL(filePath: $0.path).lastPathComponent } }

    func hash(_ path: String) -> HashedFile? {
        let call = Call(path: path, isInsideJob: pool.isInsideJob)
        recorded.withLock { $0.append(call) }
        return SourceLoader.hashedFile(atPath: path)
    }
}

extension FakeProcessRunner {
    /// A runner for which every folder lies outside every repository, so a listing scans the folder itself.
    static let outsideRepositories = FakeProcessRunner(always: .failure(128, error: "fatal: not a git repository"))
}

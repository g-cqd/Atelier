package import AemiCore
package import DiffGit
import Foundation
import Synchronization

/// How GitDiffViewer quits: it stops the work that could hold a pool thread before it shuts the pools down, and ends
/// within ``limit`` even when a pool job never returns, so AppKit gets its answer without the main thread waiting.
///
/// Diagnostics are interrupted first, then git work, which has no timeout except fetch: an interrupted run terminates
/// its child, or leaves the pool's queue before it starts, so the pools' shutdown neither waits on it nor starts it.
/// The language servers then drain while the pools' blocking shutdown runs on a thread of its own, off the main
/// thread and off the cooperative pool.
package struct ShutdownSequence: Sendable {
    /// How a run of the sequence ended.
    package enum Outcome: Sendable, Equatable {
        /// Every step finished.
        case finished
        /// ``limit`` elapsed first; the steps still running are left to the process's exit.
        case timedOut
    }

    /// Stops every diagnostics run in flight and refuses new ones.
    package var interruptDiagnostics: @Sendable () -> Void
    /// Stops every git run in flight and refuses new ones.
    package var interruptGitWork: @Sendable () -> Void
    /// Shuts the language servers down.
    package var drainLanguageServers: @Sendable () async -> Void
    /// Shuts the pools down: blocks until their workers have exited.
    package var shutdownPools: @Sendable () -> Void
    /// How long the sequence may take in all.
    package var limit: Duration
    package var clock: any Clock<Duration>
    package var taskProvider: any TaskProvider

    package init(
        interruptDiagnostics: @escaping @Sendable () -> Void,
        interruptGitWork: @escaping @Sendable () -> Void,
        drainLanguageServers: @escaping @Sendable () async -> Void,
        shutdownPools: @escaping @Sendable () -> Void,
        limit: Duration = .seconds(2),
        clock: any Clock<Duration> = ContinuousClock(),
        taskProvider: any TaskProvider = .default
    ) {
        self.interruptDiagnostics = interruptDiagnostics
        self.interruptGitWork = interruptGitWork
        self.drainLanguageServers = drainLanguageServers
        self.shutdownPools = shutdownPools
        self.limit = limit
        self.clock = clock
        self.taskProvider = taskProvider
    }

    /// Runs the sequence, and returns once every step finished or ``limit`` elapsed, whichever comes first. Steps
    /// still running at the limit go on until the process exits.
    package func run() async -> Outcome {
        interruptDiagnostics()
        interruptGitWork()
        let outcome = FirstOutcome()
        let drainLanguageServers = drainLanguageServers
        let shutdownPools = shutdownPools
        // Unstructured on purpose: past the limit, nothing may wait for these steps.
        taskProvider.task {
            async let drained: Void = drainLanguageServers()
            async let poolsDown: Void = Self.runOnThreadOfItsOwn(shutdownPools)
            _ = await (drained, poolsDown)
            outcome.resolve(.finished)
        }
        let clock = clock
        let limit = limit
        let timer = taskProvider.task {
            do {
                try await clock.sleep(for: limit)
            } catch {
                // Cancelled once every step finished: nothing is left to time.
                return
            }
            outcome.resolve(.timedOut)
        }
        let result = await outcome.value()
        timer.cancel()
        return result
    }

    /// Runs `body`, which may block for as long as it likes, on a new thread, and resumes once it returns. A blocking
    /// call must not park a thread of the cooperative pool, which is sized to the cores and not grown on demand.
    private static func runOnThreadOfItsOwn(_ body: @escaping @Sendable () -> Void) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let thread = Thread {
                body()
                continuation.resume()
            }
            thread.name = "GitDiffViewer.ShutdownSequence"
            thread.start()
        }
    }
}

/// The first outcome of the race between the steps and the limit, delivered once to the one waiter.
private final class FirstOutcome: Sendable {
    private struct State {
        var outcome: ShutdownSequence.Outcome?
        var waiter: CheckedContinuation<ShutdownSequence.Outcome, Never>?
    }

    private let state = Mutex(State())

    /// Settles the race with `outcome`, unless it is already settled.
    func resolve(_ outcome: ShutdownSequence.Outcome) {
        let waiter: CheckedContinuation<ShutdownSequence.Outcome, Never>? = state.withLock { state in
            guard state.outcome == nil else { return nil }
            state.outcome = outcome
            defer { state.waiter = nil }
            return state.waiter
        }
        waiter?.resume(returning: outcome)
    }

    /// The race's outcome, once settled.
    func value() async -> ShutdownSequence.Outcome {
        await withCheckedContinuation { (continuation: CheckedContinuation<ShutdownSequence.Outcome, Never>) in
            let settled: ShutdownSequence.Outcome? = state.withLock { state in
                if let outcome = state.outcome { return outcome }
                state.waiter = continuation
                return nil
            }
            if let settled { continuation.resume(returning: settled) }
        }
    }
}

/// A process runner that can stop every run in flight at once and refuse later ones, so quitting can stop the work
/// that would hold a pool thread: a stopped run terminates its child, or leaves the pool's queue before it starts.
package final class InterruptibleProcessRunner: ProcessRunner {
    private struct State {
        var runs: [UInt64: Task<ProcessOutput, any Error>] = [:]
        var nextID: UInt64 = 0
        var isInterrupted = false
    }

    private let base: any ProcessRunner
    private let taskProvider: any TaskProvider
    private let state = Mutex(State())

    /// - Parameters:
    ///   - base: The runner every run goes through.
    ///   - taskProvider: Spawns each run, so ``interruptAll()`` can cancel it from outside the caller's task.
    package init(base: any ProcessRunner, taskProvider: any TaskProvider = .default) {
        self.base = base
        self.taskProvider = taskProvider
    }

    /// Runs `spec` through the base runner. A cancelled caller cancels the run, as with the base runner.
    /// - Throws: `CancellationError` once ``interruptAll()`` ran, before or during the run, and whatever the base runner
    ///   throws.
    package func run(_ spec: ProcessSpec) async throws -> ProcessOutput {
        guard !state.withLock(\.isInterrupted) else { throw CancellationError() }
        let base = base
        let run = taskProvider.task { try await base.run(spec) }
        let id: UInt64? = state.withLock { state in
            guard !state.isInterrupted else { return nil }
            let id = state.nextID
            state.nextID += 1
            state.runs[id] = run
            return id
        }
        guard let id else {
            run.cancel()
            throw CancellationError()
        }
        defer { _ = state.withLock { $0.runs.removeValue(forKey: id) } }
        return try await withTaskCancellationHandler {
            try await run.value
        } onCancel: {
            run.cancel()
        }
    }

    /// Cancels every run in flight, and refuses every later one with `CancellationError`. Idempotent.
    package func interruptAll() {
        let runs: [Task<ProcessOutput, any Error>] = state.withLock { state in
            state.isInterrupted = true
            defer { state.runs.removeAll() }
            return Array(state.runs.values)
        }
        for run in runs { run.cancel() }
    }
}

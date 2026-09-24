import AemiTesting
import AtelierTestSupport
import DiffGit
import Foundation
import Synchronization
import Testing

import class AemiRuntime.BlockingOffloadPool

@testable import DiffComparison

/// The steps a sequence ran, in order.
private final class StepLog: Sendable {
    private let recorded = Mutex<[String]>([])

    var steps: [String] { recorded.withLock { $0 } }

    func record(_ step: String) {
        recorded.withLock { $0.append(step) }
    }
}

/// A width-1 pool whose one worker is stuck in a job reading a pipe nobody writes to, as a git child that never
/// exits holds its thread; ``release()`` closes the pipe, and the job returns.
private final class StuckPool: Sendable {
    let pool = BlockingOffloadPool(width: 1)
    private let pipe = Pipe()
    private let released = Mutex(false)

    /// Runs the stuck job until ``release()``; resumes once the worker has taken it.
    func stick(started: TaskGate) async throws {
        let reader = pipe.fileHandleForReading
        try await pool.run {
            started.open()
            _ = reader.readDataToEndOfFile()
        }
    }

    /// Closes the pipe the stuck job reads, once however often it is called.
    func release() throws {
        let isFirst = released.withLock { wasReleased in
            defer { wasReleased = true }
            return !wasReleased
        }
        guard isFirst else { return }
        try pipe.fileHandleForWriting.close()
    }

    /// Runs `body` once a job holds the pool's one worker, then releases the worker and awaits the job's return within
    /// the failure bound.
    ///
    /// The job is a task, and the worker is released on every way out: the job returns only once released, so an
    /// `async let` job would be awaited forever once a wait threw before the release.
    func whileStuck<Value>(_ body: (StuckJob) async throws -> Value) async throws -> Value {
        let started = TaskGate()
        let job = StuckJob(pool: self, task: Task { try await self.stick(started: started) })
        defer { try? release() }
        try await started.expectOpen()
        let value = try await body(job)
        try await job.end()
        return value
    }
}

/// The job holding a ``StuckPool``'s worker.
private struct StuckJob {
    let pool: StuckPool
    let task: Task<Void, any Error>

    /// Releases the worker, and returns once the job has, or throws ``WaitTimeout`` once the failure bound passed.
    func end(sourceLocation: SourceLocation = #_sourceLocation) async throws {
        try pool.release()
        try await task.expectValue(sourceLocation: sourceLocation)
    }
}

/// `body` on a thread of its own, since a pool's shutdown blocks until its workers exit.
private func onThreadOfItsOwn(_ body: @escaping @Sendable () -> Void) async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        Thread {
            body()
            continuation.resume()
        }
        .start()
    }
}

/// A run that leaves `marker` behind, once it starts.
private func touchSpec(_ marker: URL) -> ProcessSpec {
    ProcessSpec(executable: URL(filePath: "/usr/bin/touch"), arguments: [marker.path(percentEncoded: false)])
}

// A time limit, so a sequence or runner that never lets go fails the run instead of hanging it.
@Suite(.timeLimit(.minutes(1)))
struct ShutdownSequenceTests {
    @Test
    func `diagnostics are interrupted first, then git work, and both before anything drains or shuts down`() async {
        let log = StepLog()
        let sequence = ShutdownSequence(
            interruptDiagnostics: { log.record("diagnostics") }, interruptGitWork: { log.record("git") },
            drainLanguageServers: { log.record("language servers") }, shutdownPools: { log.record("pools") },
            clock: TestClock(), taskProvider: TaskProviderSpy.tolerant())

        let outcome = await sequence.run()

        #expect(outcome == .finished)
        #expect(Array(log.steps.prefix(2)) == ["diagnostics", "git"])
        #expect(Set(log.steps.dropFirst(2)) == ["language servers", "pools"])
    }

    /// Runs a sequence with a 2 s limit over a pool whose one worker is stuck, advances the clock past the limit once
    /// `awaitingSleeper` has seen the sequence's timer registered, and returns the sequence's outcome.
    ///
    /// The sequence runs in a task awaited within the failure bound, and the stuck job ends on every way out: the
    /// sequence's pool shutdown returns only once the job does, so neither may be an `async let` a failed wait leaves
    /// behind.
    private func outcomeOverAStuckPool(
        awaitingSleeper: (TestClock, TestClock.RegistrationMark) async throws -> Void
    ) async throws -> ShutdownSequence.Outcome {
        let clock = TestClock()
        let tasks = TaskProviderSpy.tolerant()
        let stuck = StuckPool()
        let result = try await stuck.whileStuck { job in
            let pool = stuck.pool
            let sequence = ShutdownSequence(
                interruptDiagnostics: {}, interruptGitWork: {}, drainLanguageServers: {},
                shutdownPools: { pool.shutdown() }, limit: .seconds(2), clock: clock, taskProvider: tasks)

            let mark = clock.registrationMark()
            let outcome = Task { await sequence.run() }
            try await awaitingSleeper(clock, mark)
            clock.advance(by: .seconds(2))
            let result = try await outcome.expectValue()
            // The abandoned shutdown finishes once the stuck job returns.
            try await job.end()
            return result
        }
        try await tasks.waitForAllTasks()
        return result
    }

    @Test
    func `the sequence ends at its limit when a pool job never returns`() async throws {
        let outcome = try await outcomeOverAStuckPool { clock, mark in
            try await clock.expectSleepers(after: mark)
        }

        #expect(outcome == .timedOut)
    }

    /// A wait that fails before the stuck job is released must fail the test with its error, not leave the test
    /// waiting forever on a job, and a sequence, that only the release lets end.
    @Test
    func `a failed wait for the sequence's timer ends the stuck job instead of hanging the test`() async throws {
        struct SleeperNotSeen: Error {}

        let failedWithTheWait = try await withFailureBound(awaiting: "The stuck job's end after a failed wait") {
            do {
                _ = try await outcomeOverAStuckPool { _, _ in throw SleeperNotSeen() }
                return false
            } catch is SleeperNotSeen {
                return true
            }
        }

        #expect(failedWithTheWait)
    }
}

@Suite(.timeLimit(.minutes(1)))
struct InterruptibleProcessRunnerTests {
    private let spec = ProcessSpec(executable: URL(filePath: "/usr/bin/true"))

    @Test
    func `interrupting cancels a run in flight`() async throws {
        let entered = TaskGate()
        let sawCancellation = TaskGate()
        let base = FakeProcessRunner { _ in
            entered.open()
            do {
                // Never opened: the run lasts until it is cancelled.
                try await TaskGate().wait()
            } catch {
                sawCancellation.open()
                throw error
            }
            return .success("never")
        }
        let runner = InterruptibleProcessRunner(base: base, taskProvider: TaskProviderSpy.tolerant())

        async let run = runner.run(spec)
        try await entered.expectOpen()
        runner.interruptAll()
        let outcome: Result<ProcessOutput, any Error>
        do { outcome = .success(try await run) } catch { outcome = .failure(error) }

        #expect(throws: CancellationError.self) { try outcome.get() }
        try await sawCancellation.expectOpen()
    }

    @Test
    func `a run after the interruption is refused before it reaches the base runner`() async {
        let base = FakeProcessRunner(always: .success("output"))
        let runner = InterruptibleProcessRunner(base: base, taskProvider: TaskProviderSpy.tolerant())
        runner.interruptAll()

        await #expect(throws: CancellationError.self) { try await runner.run(spec) }
        #expect(base.specs.isEmpty)
    }

    @Test
    func `a run nobody interrupts returns the base runner's output`() async throws {
        let base = FakeProcessRunner(always: .success("output"))
        let runner = InterruptibleProcessRunner(base: base, taskProvider: TaskProviderSpy.tolerant())

        let output = try await runner.run(spec)

        #expect(output == .success("output"))
        #expect(base.specs == [spec])
    }

    @Test
    func `an interrupted run waiting for a pool thread never starts, even when the pool shuts down`() async throws {
        let scratch = FileManager.default.temporaryDirectory.appending(
            path: "gdv-interrupt-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let marker = scratch.appending(path: "marker")
        let stuck = StuckPool()
        // The run is a task, and the stuck job ends on every way out: see `StuckPool.whileStuck(_:)`.
        let outcome = try await stuck.whileStuck { job in
            let hardened = HardenedProcessRunner(pool: stuck.pool)
            let reachedPoolRunner = TaskGate()
            let base = FakeProcessRunner { spec in
                reachedPoolRunner.open()
                return try await hardened.run(spec)
            }
            let runner = InterruptibleProcessRunner(base: base, taskProvider: TaskProviderSpy.tolerant())

            let queued = Task { try await runner.run(touchSpec(marker)) }
            try await reachedPoolRunner.expectOpen()
            runner.interruptAll()
            // The worker is free again before the run ends: an interruption that left the job queued would run it now.
            try await job.end()
            return try await queued.expectResult()
        }
        let pool = stuck.pool
        await onThreadOfItsOwn { pool.shutdown() }

        #expect(throws: CancellationError.self) { try outcome.get() }
        #expect(!FileManager.default.fileExists(atPath: marker.path(percentEncoded: false)))
    }
}

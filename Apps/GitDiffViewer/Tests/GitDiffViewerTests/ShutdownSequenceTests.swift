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

    /// Runs the stuck job until ``release()``; resumes once the worker has taken it.
    func stick(started: TaskGate) async throws {
        let reader = pipe.fileHandleForReading
        try await pool.run {
            started.open()
            _ = reader.readDataToEndOfFile()
        }
    }

    func release() throws {
        try pipe.fileHandleForWriting.close()
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

    @Test
    func `the sequence ends at its limit when a pool job never returns`() async throws {
        let clock = TestClock()
        let tasks = TaskProviderSpy.tolerant()
        let stuck = StuckPool()
        let started = TaskGate()
        async let job: Void = stuck.stick(started: started)
        try await started.wait()
        let pool = stuck.pool
        let sequence = ShutdownSequence(
            interruptDiagnostics: {}, interruptGitWork: {}, drainLanguageServers: {},
            shutdownPools: { pool.shutdown() }, limit: .seconds(2), clock: clock, taskProvider: tasks)

        async let outcome = sequence.run()
        try await clock.waitForSleepers(count: 1)
        clock.advance(by: .seconds(2))

        #expect(await outcome == .timedOut)
        // The abandoned shutdown finishes once the stuck job returns.
        try stuck.release()
        try await job
        try await tasks.waitForAllTasks()
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
        try await entered.wait()
        runner.interruptAll()
        let outcome: Result<ProcessOutput, any Error>
        do { outcome = .success(try await run) } catch { outcome = .failure(error) }

        #expect(throws: CancellationError.self) { try outcome.get() }
        try await sawCancellation.wait()
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
        let started = TaskGate()
        async let job: Void = stuck.stick(started: started)
        try await started.wait()
        let hardened = HardenedProcessRunner(pool: stuck.pool)
        let reachedPoolRunner = TaskGate()
        let base = FakeProcessRunner { spec in
            reachedPoolRunner.open()
            return try await hardened.run(spec)
        }
        let runner = InterruptibleProcessRunner(base: base, taskProvider: TaskProviderSpy.tolerant())

        async let queued = runner.run(touchSpec(marker))
        try await reachedPoolRunner.wait()
        runner.interruptAll()
        // The worker is free again before the run ends: an interruption that left the job queued would run it now.
        try stuck.release()
        try await job
        let outcome: Result<ProcessOutput, any Error>
        do { outcome = .success(try await queued) } catch { outcome = .failure(error) }
        let pool = stuck.pool
        await onThreadOfItsOwn { pool.shutdown() }

        #expect(throws: CancellationError.self) { try outcome.get() }
        #expect(!FileManager.default.fileExists(atPath: marker.path(percentEncoded: false)))
    }
}

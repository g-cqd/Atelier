import AemiRuntime
import AemiTestKit
import Foundation
import Testing

@testable import AtelierProcess

/// The runner against real children from `/bin`; the timeout is driven by a virtual clock.
@Suite(.tags(.concurrency))
struct HardenedProcessRunnerTests {
    private static func shell(_ script: String, timeout: Duration? = nil, input: Data? = nil) -> ProcessSpec {
        ProcessSpec(
            executable: URL(filePath: "/bin/sh"), arguments: ["-c", script], standardInput: input, timeout: timeout)
    }

    @Test(.timeLimit(.minutes(1)))
    func `captures both outputs and the exit status`() async throws {
        let pool = BlockingOffloadPool(width: 2)
        defer { pool.shutdown() }
        let runner = HardenedProcessRunner(pool: pool)
        let output = try await runner.run(Self.shell("printf out; printf ' err ' >&2; exit 3"))
        #expect(output.terminationStatus == 3)
        #expect(!output.succeeded)
        #expect(String(decoding: output.standardOutput, as: UTF8.self) == "out")
        #expect(output.errorText == "err")
    }

    @Test(.timeLimit(.minutes(1)))
    func `feeds the standard input from the spec and closes it`() async throws {
        let pool = BlockingOffloadPool(width: 2)
        defer { pool.shutdown() }
        let runner = HardenedProcessRunner(pool: pool)
        let output = try await runner.run(Self.shell("cat", input: Data("hello\n".utf8)))
        #expect(output.succeeded)
        #expect(String(decoding: output.standardOutput, as: UTF8.self) == "hello\n")
        // No input: the child reads an end of file at once instead of waiting on the parent's terminal.
        let closed = try await runner.run(Self.shell("cat; echo done"))
        #expect(String(decoding: closed.standardOutput, as: UTF8.self) == "done\n")
    }

    @Test(.timeLimit(.minutes(1)))
    func `an exact environment replaces the inherited one`() async throws {
        let pool = BlockingOffloadPool(width: 2)
        defer { pool.shutdown() }
        let runner = HardenedProcessRunner(pool: pool)
        let spec = ProcessSpec(executable: URL(filePath: "/usr/bin/env"), environment: .exactly(["ONLY": "1"]))
        let output = try await runner.run(spec)
        #expect(String(decoding: output.standardOutput, as: UTF8.self) == "ONLY=1\n")
    }

    @Test(.timeLimit(.minutes(1)))
    func `overrides sit on top of the inherited environment`() async throws {
        let pool = BlockingOffloadPool(width: 2)
        defer { pool.shutdown() }
        let runner = HardenedProcessRunner(pool: pool)
        let spec = ProcessSpec(
            executable: URL(filePath: "/bin/sh"), arguments: ["-c", "printf '%s|%s' \"$HOME\" \"$ATELIER_PROBE\""],
            environment: .inherited(overriding: ["ATELIER_PROBE": "set"]))
        let output = try await runner.run(spec)
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
        #expect(String(decoding: output.standardOutput, as: UTF8.self) == "\(home)|set")
    }

    @Test(.timeLimit(.minutes(1)))
    func `a child that ignores the termination is killed after the grace period`() async throws {
        let pool = BlockingOffloadPool(width: 2)
        defer { pool.shutdown() }
        let clock = TestClock()
        let runner = HardenedProcessRunner(pool: pool, clock: clock)
        // `trap '' TERM` makes the shell ignore SIGTERM; only SIGKILL ends it.
        let run = Task { try await runner.run(Self.shell("trap '' TERM; sleep 60", timeout: .seconds(5))) }
        try await clock.waitForSleepers(atLeast: 1)
        clock.advance(by: .seconds(5))
        // The timeout sleeper left the queue when it fired; the grace sleeper is the only one that can be queued now.
        try await clock.waitForSleepers(atLeast: 1)
        clock.advance(by: HardenedProcessRunner.killGracePeriod)
        await #expect(throws: ProcessError.timedOut(.seconds(5))) { try await run.value }
    }

    @Test(.timeLimit(.minutes(1)))
    func `a missing executable fails to launch`() async throws {
        let pool = BlockingOffloadPool(width: 2)
        defer { pool.shutdown() }
        let runner = HardenedProcessRunner(pool: pool)
        let spec = ProcessSpec(executable: URL(filePath: "/nonexistent/tool"))
        await #expect(throws: ProcessError.self) { try await runner.run(spec) }
    }

    @Test(.timeLimit(.minutes(1)))
    func `the timeout on the injected clock terminates a child that runs too long`() async throws {
        let pool = BlockingOffloadPool(width: 2)
        defer { pool.shutdown() }
        let clock = TestClock()
        let runner = HardenedProcessRunner(pool: pool, clock: clock)
        let run = Task { try await runner.run(Self.shell("sleep 60", timeout: .seconds(5))) }
        try await clock.waitForSleepers(atLeast: 1)
        clock.advance(by: .seconds(5))
        await #expect(throws: ProcessError.timedOut(.seconds(5))) { try await run.value }
    }

    @Test(.timeLimit(.minutes(1)))
    func `cancelling the caller terminates the child and surfaces the cancellation`() async throws {
        let pool = BlockingOffloadPool(width: 2)
        defer { pool.shutdown() }
        let runner = HardenedProcessRunner(pool: pool)
        let run = Task { try await runner.run(Self.shell("sleep 60")) }
        run.cancel()
        await #expect(throws: CancellationError.self) { try await run.value }
    }
}

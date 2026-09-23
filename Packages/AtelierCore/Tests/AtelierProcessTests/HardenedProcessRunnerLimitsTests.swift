import AemiRuntime
import AemiTestKit
import Darwin
import Foundation
import Testing

@testable import AtelierProcess

/// What a child can do to the runner that runs it: write without end, leave grandchildren on its pipes, ignore its
/// termination. Real children from `/bin`; deadlines on a virtual clock, and readiness through a FIFO the child writes.
@Suite(.tags(.concurrency))
struct HardenedProcessRunnerLimitsTests {
    private static func shell(
        _ script: String, timeout: Duration? = nil, input: Data? = nil, outputLimit: Int? = nil,
        errorLimit: Int? = nil
    ) -> ProcessSpec {
        ProcessSpec(
            executable: URL(filePath: "/bin/sh"), arguments: ["-c", script], standardInput: input, timeout: timeout,
            standardOutputLimit: outputLimit ?? ProcessSpec.defaultStandardOutputLimit,
            standardErrorLimit: errorLimit ?? ProcessSpec.defaultStandardErrorLimit)
    }

    @Test(.timeLimit(.minutes(1)))
    func `standard output past its limit terminates the child and fails the run`() async throws {
        let pool = BlockingOffloadPool(width: 2)
        defer { pool.shutdown() }
        let directory = TemporaryDirectory(prefix: "atelier-runner")
        defer { directory.cleanup() }
        let finished = directory.file("finished")
        // The pipe holds far less than a mebibyte, so `head` is still writing when the limit is passed.
        let spec = Self.shell("head -c 1048576 /dev/zero; touch '\(finished)'", outputLimit: 65_536)
        await #expect(throws: ProcessError.outputLimitExceeded(.standardOutput, limit: 65_536)) {
            try await HardenedProcessRunner(pool: pool).run(spec)
        }
        #expect(!FileManager.default.fileExists(atPath: finished))
    }

    @Test(.timeLimit(.minutes(1)))
    func `standard error past its limit terminates the child and fails the run`() async throws {
        let pool = BlockingOffloadPool(width: 2)
        defer { pool.shutdown() }
        let directory = TemporaryDirectory(prefix: "atelier-runner")
        defer { directory.cleanup() }
        let finished = directory.file("finished")
        let spec = Self.shell("head -c 1048576 /dev/zero >&2; touch '\(finished)'", errorLimit: 65_536)
        await #expect(throws: ProcessError.outputLimitExceeded(.standardError, limit: 65_536)) {
            try await HardenedProcessRunner(pool: pool).run(spec)
        }
        #expect(!FileManager.default.fileExists(atPath: finished))
    }

    @Test(.timeLimit(.minutes(1)))
    func `output exactly at its limit is kept whole`() async throws {
        let pool = BlockingOffloadPool(width: 2)
        defer { pool.shutdown() }
        let output = try await HardenedProcessRunner(pool: pool)
            .run(
                Self.shell(
                    "head -c 65536 /dev/zero; head -c 1024 /dev/zero >&2", outputLimit: 65_536, errorLimit: 1_024))
        #expect(output.succeeded)
        #expect(output.standardOutput.count == 65_536)
        #expect(output.standardError.count == 1_024)
    }

    @Test(.timeLimit(.minutes(1)))
    func `a grandchild still holding standard output does not hold the run once the child exits`() async throws {
        let pool = BlockingOffloadPool(width: 2)
        defer { pool.shutdown() }
        // The background `sleep` inherits the pipe and keeps it open well past the time limit.
        let output = try await HardenedProcessRunner(pool: pool).run(Self.shell("sleep 120 & echo $!"))
        let grandchild = try #require(
            Int32(
                String(decoding: output.standardOutput, as: UTF8.self)
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines)))
        kill(grandchild, SIGKILL)
        #expect(output.succeeded)
    }

    /// Blocks on the pool until the child writes `ready` into the FIFO at `path`.
    private static func awaitReady(_ path: String, on pool: BlockingOffloadPool) async throws {
        let signal = try await pool.run { try FileHandle(forReadingFrom: URL(filePath: path)).readToEnd() }
        #expect(signal == Data("ready\n".utf8))
    }

    @Test(.timeLimit(.minutes(1)))
    func `a child that leaves a grandchild holding standard output returns within its timeout and grace period`()
        async throws
    {
        let pool = BlockingOffloadPool(width: 2)
        defer { pool.shutdown() }
        let clock = TestClock()
        let runner = HardenedProcessRunner(pool: pool, clock: clock)
        let directory = TemporaryDirectory(prefix: "atelier-runner")
        defer { directory.cleanup() }
        let ready = directory.file("ready")
        #expect(mkfifo(ready, 0o600) == 0)
        // Both ignore `SIGTERM`, and the background one holds the pipe; only `SIGKILL` ends them.
        let script = "trap '' TERM; sleep 120 & echo ready > '\(ready)'; sleep 120"
        let run = Task { try await runner.run(Self.shell(script, timeout: .seconds(5))) }
        try await Self.awaitReady(ready, on: pool)
        try await clock.waitForSleepers(atLeast: 1)
        clock.advance(by: .seconds(5))
        try await clock.waitForSleepers(atLeast: 1)
        clock.advance(by: HardenedProcessRunner.killGracePeriod)
        await #expect(throws: ProcessError.timedOut(.seconds(5))) { try await run.value }
    }

    @Test(.timeLimit(.minutes(1)))
    func `the termination reaches the grandchildren in the child's process group`() async throws {
        let pool = BlockingOffloadPool(width: 2)
        defer { pool.shutdown() }
        let clock = TestClock()
        let runner = HardenedProcessRunner(pool: pool, clock: clock)
        let directory = TemporaryDirectory(prefix: "atelier-runner")
        defer { directory.cleanup() }
        let ready = directory.file("ready")
        #expect(mkfifo(ready, 0o600) == 0)
        // The shell survives `SIGTERM` through its trap and exits once its background `sleep` is gone, which only a
        // signal to the whole group brings about before the time limit. The background job reports ready itself,
        // from a fresh shell, once the trap is gone: a fork of this shell that has not yet started `sleep` would
        // catch the signal with the trap and then sleep on, which a loaded machine makes likely.
        let script = "trap ':' TERM; sh -c \"echo ready > '\(ready)'; exec sleep 120\" & c=$!; wait $c; wait $c"
        let run = Task { try await runner.run(Self.shell(script, timeout: .seconds(5))) }
        try await Self.awaitReady(ready, on: pool)
        try await clock.waitForSleepers(atLeast: 1)
        clock.advance(by: .seconds(5))
        await #expect(throws: ProcessError.timedOut(.seconds(5))) { try await run.value }
    }

    @Test(.timeLimit(.minutes(1)))
    func `the kill after the grace period reaches the grandchildren in the child's process group`() async throws {
        let pool = BlockingOffloadPool(width: 3)
        defer { pool.shutdown() }
        let clock = TestClock()
        let runner = HardenedProcessRunner(pool: pool, clock: clock)
        let directory = TemporaryDirectory(prefix: "atelier-runner")
        defer { directory.cleanup() }
        let ready = directory.file("ready")
        let held = directory.file("held")
        #expect(mkfifo(ready, 0o600) == 0 && mkfifo(held, 0o600) == 0)
        // Opened for reading first, so the grandchild's open for writing does not wait; the read below then ends
        // only when the grandchild, the one writer, is gone.
        let reading = open(held, O_RDONLY | O_NONBLOCK)
        #expect(reading >= 0)
        defer { close(reading) }
        // Everything ignores `SIGTERM`, and the grandchild writes to `held` and to nothing of the runner's.
        let script = "trap '' TERM; (echo ready > '\(ready)'; exec sleep 120) > '\(held)' & wait"
        let run = Task { try await runner.run(Self.shell(script, timeout: .seconds(5))) }
        try await Self.awaitReady(ready, on: pool)
        _ = fcntl(reading, F_SETFL, 0)
        async let grandchildGone: Int = pool.run {
            var byte: UInt8 = 0
            return read(reading, &byte, 1)
        }
        try await clock.waitForSleepers(atLeast: 1)
        clock.advance(by: .seconds(5))
        try await clock.waitForSleepers(atLeast: 1)
        clock.advance(by: HardenedProcessRunner.killGracePeriod)
        await #expect(throws: ProcessError.timedOut(.seconds(5))) { try await run.value }
        #expect(try await grandchildGone == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func `standard input comes from a file with no path left for anyone to open`() async throws {
        let pool = BlockingOffloadPool(width: 2)
        defer { pool.shutdown() }
        // The link count of the file the child reads its input from, then the input itself.
        let output = try await HardenedProcessRunner(pool: pool)
            .run(Self.shell("stat -f %l /dev/fd/0; cat", input: Data("payload\n".utf8)))
        #expect(String(decoding: output.standardOutput, as: UTF8.self) == "0\npayload\n")
    }
}

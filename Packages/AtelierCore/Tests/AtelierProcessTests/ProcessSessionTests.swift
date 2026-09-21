import AemiTestKit
import Foundation
import Testing

@testable import AtelierProcess

/// A ``ProcessSession`` over real children from `/bin`.
@Suite(.tags(.concurrency))
struct ProcessSessionTests {
    private static func session(
        _ executable: String, _ arguments: [String] = [], killGracePeriod: Duration = .seconds(2)
    ) -> ProcessSession {
        ProcessSession(
            executable: URL(filePath: executable), arguments: arguments, killGracePeriod: killGracePeriod)
    }

    /// Drains `output` until the stream finishes, collecting every chunk it yields.
    private static func drain(_ output: AsyncThrowingStream<Data, any Error>) async throws -> Data {
        var collected = Data()
        for try await chunk in output {
            collected.append(chunk)
        }
        return collected
    }

    @Test(.timeLimit(.minutes(1)))
    func `echoes writes back in order over cat`() async throws {
        let session = Self.session("/bin/cat")
        try await session.start()
        let expected = Data("hello world".utf8)
        let reader = Task { () -> Data in
            var collected = Data()
            for try await chunk in session.output {
                collected.append(chunk)
                if collected.count >= expected.count { return collected }
            }
            return collected
        }
        try await session.send(Data("hello ".utf8))
        try await session.send(Data("world".utf8))
        let collected = try await reader.value
        #expect(collected == expected)
        await session.terminate()
        _ = await session.waitForExit()
    }

    @Test(.timeLimit(.minutes(1)))
    func `reports the child's exit status`() async throws {
        let session = Self.session("/bin/sh", ["-c", "exit 3"])
        try await session.start()
        // Draining the stream to its end proves it finishes when the child exits.
        let collected = try await Self.drain(session.output)
        #expect(collected.isEmpty)
        #expect(await session.waitForExit() == 3)
    }

    @Test(.timeLimit(.minutes(1)))
    func `rolls standard error into the capped tail`() async throws {
        let session = Self.session("/bin/sh", ["-c", "echo err 1>&2; cat"])
        try await session.start()
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while await session.stderrSnapshot().isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let stderrTail = await session.stderrSnapshot()
        #expect(String(decoding: stderrTail, as: UTF8.self).contains("err"))
        await session.terminate()
        _ = await session.waitForExit()
    }

    @Test(.timeLimit(.minutes(1)))
    func `terminate kills a long runner and ends its output`() async throws {
        let session = Self.session("/bin/cat")
        try await session.start()
        let reader = Task { try await Self.drain(session.output) }
        await session.terminate()
        _ = try await reader.value
        let status = await session.waitForExit()
        #expect(status != 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func `send before start throws notRunning`() async throws {
        let session = Self.session("/bin/cat")
        do {
            try await session.send(Data("hi".utf8))
            Issue.record("expected notRunning")
        } catch ProcessSessionError.notRunning {
            // Expected.
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func `send after exit throws`() async throws {
        let session = Self.session("/bin/sh", ["-c", "exit 0"])
        try await session.start()
        _ = await session.waitForExit()
        await #expect(throws: ProcessSessionError.self) {
            try await session.send(Data("hi".utf8))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func `delivers large output without hanging`() async throws {
        let session = Self.session("/bin/sh", ["-c", "dd if=/dev/zero bs=65536 count=64 2>/dev/null"])
        try await session.start()
        let collected = try await Self.drain(session.output)
        #expect(collected.count == 64 * 65_536)
        #expect(await session.waitForExit() == 0)
    }
}

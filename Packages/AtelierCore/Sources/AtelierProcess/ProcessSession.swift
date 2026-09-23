public import Foundation
import Subprocess

#if canImport(System)
    import System
#else
    import SystemPackage
#endif

/// A long-lived child speaking over stdin/stdout, e.g. a language server.
///
/// One unstructured task owns the child for its whole life: it holds the swift-subprocess `run` call open, forwards
/// standard output into ``output`` and keeps a capped tail of standard error. swift-subprocess drives the pipes, so
/// no read occupies a blocking-pool thread. ``terminate()`` cancels that task, which sends `SIGTERM`, then `SIGKILL`
/// after ``killGracePeriod``.
public actor ProcessSession {
    /// How long a terminated child gets to exit after `SIGTERM` before `SIGKILL`.
    private let killGracePeriod: Duration
    private let executable: URL
    private let arguments: [String]
    private let environmentVariables: [String: String]?
    private let workingDirectory: URL?

    /// Raw stdout chunks in arrival order. Single consumer. The stream finishes, without an error, once the
    /// child has exited; call ``waitForExit()`` to learn its exit status.
    public nonisolated let output: AsyncThrowingStream<Data, any Error>
    private let outputContinuation: AsyncThrowingStream<Data, any Error>.Continuation

    private enum State {
        /// Never started.
        case idle
        /// ``start()`` is waiting for the child to spawn.
        case launching
        /// The child is running; writes go through this writer.
        case running(StandardInputWriter)
        /// The child has exited with this status.
        case exited(Int32)
    }

    private var state: State = .idle
    /// The task that owns the swift-subprocess `run` call for the child's whole life.
    private var runTask: Task<Void, Never>?
    /// Resumed once, either when the child's `Execution` is available or when the launch fails.
    private var readyContinuation: CheckedContinuation<Void, any Error>?
    private var exitWaiters: [CheckedContinuation<Int32, Never>] = []
    private var stderrTail = Data()

    /// True while one ``send(_:)`` holds the write slot. A write suspends across its retries, so without this FIFO
    /// slot concurrent sends could interleave their bytes on stdin and break the message framing.
    private var writeInFlight = false
    private var writeWaiters: [CheckedContinuation<Void, Never>] = []

    /// The most stderr bytes ``stderrSnapshot()`` keeps.
    private static let stderrCapacity = 64 * 1_024

    public init(
        executable: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        workingDirectory: URL? = nil,
        killGracePeriod: Duration = .seconds(2)
    ) {
        self.executable = executable
        self.arguments = arguments
        self.environmentVariables = environment
        self.workingDirectory = workingDirectory
        self.killGracePeriod = killGracePeriod
        let (stream, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()
        self.output = stream
        self.outputContinuation = continuation
    }

    /// Launches the child and waits until it is running. A second call while already running or launched is a
    /// no-op.
    /// - Throws: ``ProcessSessionError/launchFailed(_:)`` when swift-subprocess could not spawn the child.
    public func start() async throws {
        guard runTask == nil else { return }
        state = .launching
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                readyContinuation = continuation
                runTask = Task { [weak self] in
                    await self?.runChild()
                }
            }
        } catch {
            state = .idle
            runTask = nil
            throw error
        }
    }

    /// Writes all of `data` to the child's stdin, queued FIFO behind any ``send(_:)`` already in flight.
    /// - Throws: ``ProcessSessionError/notRunning`` before ``start()`` has reached a running child,
    ///   ``ProcessSessionError/exited(status:stderrTail:)`` once the child has exited, or
    ///   ``ProcessSessionError/writeFailed(_:)`` when the write itself fails or stalls with no progress.
    public func send(_ data: Data) async throws {
        await acquireWriteSlot()
        defer { releaseWriteSlot() }

        switch state {
            case .idle, .launching:
                throw ProcessSessionError.notRunning
            case .exited(let status):
                throw ProcessSessionError.exited(status: status, stderrTail: stderrTail)
            case .running(let writer):
                try await writeFully(data, using: writer)
        }
    }

    /// Writes every byte of `data`, since ``StandardInputWriter/write(_:)`` can accept fewer without throwing.
    private func writeFully(_ data: Data, using writer: StandardInputWriter) async throws {
        var remaining = data
        while !remaining.isEmpty {
            let written: Int
            do {
                written = try await writer.write(remaining)
            } catch {
                throw ProcessSessionError.writeFailed(String(describing: error))
            }
            guard written > 0 else {
                throw ProcessSessionError.writeFailed(
                    "write accepted 0 of \(remaining.count) remaining byte(s); the child is likely gone")
            }
            remaining = remaining.dropFirst(written)
        }
    }

    /// Suspends until this call holds the write slot; waiters get it in FIFO order.
    private func acquireWriteSlot() async {
        guard writeInFlight else {
            writeInFlight = true
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writeWaiters.append(continuation)
        }
    }

    private func releaseWriteSlot() {
        guard !writeWaiters.isEmpty else {
            writeInFlight = false
            return
        }
        // Handing over without clearing `writeInFlight` keeps a send arriving in between from jumping the queue.
        writeWaiters.removeFirst().resume()
    }

    /// `SIGTERM`, then `SIGKILL` after ``killGracePeriod``. Safe when never started; returns once the child, if
    /// any, has exited.
    public func terminate() async {
        guard let runTask else { return }
        runTask.cancel()
        await runTask.value
    }

    /// The child's exit status, once it has exited.
    public func waitForExit() async -> Int32 {
        if case .exited(let status) = state { return status }
        return await withCheckedContinuation { continuation in
            exitWaiters.append(continuation)
        }
    }

    /// A rolling tail of stderr, capped at 64 KiB.
    public func stderrSnapshot() -> Data { stderrTail }

    // MARK: - The owning task

    /// Spawns the child, streams its output and error, and reports its exit; runs on the task ``start()`` creates.
    private func runChild() async {
        do {
            let result = try await Subprocess.run(
                .path(FilePath(executable.path)),
                arguments: Arguments(arguments),
                environment: Self.subprocessEnvironment(environmentVariables),
                workingDirectory: workingDirectory.map { FilePath($0.path) },
                platformOptions: Self.platformOptions(killGracePeriod: killGracePeriod),
                input: .inputWriter,
                output: .sequence,
                error: .sequence
            ) { [weak self] execution in
                guard let self else { return }
                await self.attach(writer: execution.standardInputWriter)
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        for try await buffer in execution.standardOutput {
                            await self.forwardOutput(Data(buffer: buffer))
                        }
                    }
                    group.addTask {
                        for try await buffer in execution.standardError {
                            await self.appendStderr(Data(buffer: buffer))
                        }
                    }
                    try await group.waitForAll()
                }
            }
            finish(status: Self.exitCode(from: result.terminationStatus))
        } catch {
            failedToLaunchOrExited(with: error)
        }
    }

    private func attach(writer: StandardInputWriter) {
        state = .running(writer)
        readyContinuation?.resume()
        readyContinuation = nil
    }

    private func forwardOutput(_ data: Data) {
        outputContinuation.yield(data)
    }

    private func appendStderr(_ data: Data) {
        stderrTail.append(data)
        if stderrTail.count > Self.stderrCapacity {
            stderrTail.removeFirst(stderrTail.count - Self.stderrCapacity)
        }
    }

    private func finish(status: Int32) {
        state = .exited(status)
        outputContinuation.finish()
        let waiters = exitWaiters
        exitWaiters.removeAll()
        for waiter in waiters { waiter.resume(returning: status) }
    }

    /// Fails a pending ``start()`` when the launch produced no `Execution`; otherwise the running child has ended.
    private func failedToLaunchOrExited(with error: any Error) {
        if let readyContinuation {
            self.readyContinuation = nil
            state = .idle
            readyContinuation.resume(throwing: ProcessSessionError.launchFailed(String(describing: error)))
            return
        }
        finish(status: -1)
    }

    private static func exitCode(from status: TerminationStatus) -> Int32 {
        switch status {
            case .exited(let code): code
            case .signaled(let code): -code
        }
    }

    private static func platformOptions(killGracePeriod: Duration) -> PlatformOptions {
        var options = PlatformOptions()
        options.teardownSequence = [.gracefulShutDown(allowedDurationToNextStep: killGracePeriod)]
        return options
    }

    /// `nil` inherits the parent's environment untouched; otherwise the child sees exactly these variables.
    private static func subprocessEnvironment(_ variables: [String: String]?) -> Environment {
        guard let variables else { return .inherit }
        let entries = variables.map { (Environment.Key(rawValue: $0.key)!, $0.value) }
        return .custom(Dictionary(uniqueKeysWithValues: entries))
    }
}

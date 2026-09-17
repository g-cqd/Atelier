public import AemiRuntime
import Darwin
public import Foundation
import Synchronization

/// Runs a child through `Process` with one blocking job on aemi's pool per run.
///
/// The child's standard error and, when given, its standard input go through temporary files, so the one job only
/// reads standard output and waits for the exit: no job ever waits on another job for a pool thread, whatever the
/// pool width, and a full standard error can never stall the standard output. Cancelling the calling task
/// terminates the child, whether or not it has been launched yet. A spec with a timeout races the job against the
/// runner's clock, so a test drives the deadline with a virtual clock. A child that ignores the termination a
/// timeout sends is killed after ``killGracePeriod``; a cancellation only sends the termination, since a
/// cancellation handler has no clock to wait on.
public struct HardenedProcessRunner: ProcessRunner {
    /// How long a timed-out child gets to exit after `SIGTERM` before `SIGKILL`.
    public static let killGracePeriod: Duration = .seconds(2)

    private let pool: BlockingOffloadPool
    private let clock: any Clock<Duration>

    /// - Parameters:
    ///   - pool: The threads blocking reads run on; sized by the caller for the concurrency it wants.
    ///   - clock: The clock timeouts are measured on.
    public init(pool: BlockingOffloadPool, clock: any Clock<Duration> = ContinuousClock()) {
        self.pool = pool
        self.clock = clock
    }

    public func run(_ spec: ProcessSpec) async throws -> ProcessOutput {
        let running = LaunchedProcess()
        let scratch = try ScratchFiles(input: spec.standardInput)
        defer { scratch.remove() }
        return try await withTaskCancellationHandler {
            let output = try await withTimeout(spec.timeout, running: running) {
                try await pool.run { try Self.launch(spec, scratch: scratch, tracking: running) }
            }
            if running.isCancelled { throw CancellationError() }
            return output
        } onCancel: {
            running.terminate()
        }
    }

    /// Runs `job`, terminating the child and throwing ``ProcessError/timedOut(_:)`` if `timeout` elapses first.
    private func withTimeout(
        _ timeout: Duration?, running: LaunchedProcess, _ job: @escaping @Sendable () async throws -> ProcessOutput
    ) async throws -> ProcessOutput {
        guard let timeout else { return try await job() }
        let clock = clock
        return try await withThrowingTaskGroup(of: ProcessOutput?.self) { group in
            group.addTask { try await job() }
            group.addTask {
                try await clock.sleep(for: timeout)
                return nil
            }
            defer { group.cancelAll() }
            while let result = try await group.next() {
                if let result { return result }
                // The deadline came first: the child has to go, and its job returns once it is gone. A child that
                // ignores the termination is killed after the grace period, so the job cannot hold its thread.
                running.terminate()
                group.addTask {
                    try await clock.sleep(for: Self.killGracePeriod)
                    running.kill()
                    return nil
                }
                while let late = try await group.next() {
                    if late != nil { break }
                }
                throw ProcessError.timedOut(timeout)
            }
            throw ProcessError.launchFailed("the run produced no result")
        }
    }

    /// Starts the child, reads its standard output to the end and waits for it to exit. Blocks: runs on the pool.
    private static func launch(
        _ spec: ProcessSpec, scratch: ScratchFiles, tracking running: LaunchedProcess
    ) throws -> ProcessOutput {
        let process = Process()
        process.executableURL = spec.executable
        process.arguments = spec.arguments
        process.currentDirectoryURL = spec.currentDirectory
        if let variables = spec.environment.variables { process.environment = variables }
        let output = Pipe()
        process.standardOutput = output
        process.standardError = try scratch.errorHandle()
        process.standardInput = try scratch.inputHandle()
        do {
            try running.start(process)
        } catch {
            // With no child holding the write end, the reader would wait for an end of file that never comes.
            try? output.fileHandleForWriting.close()
            throw ProcessError.launchFailed(error.localizedDescription)
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return ProcessOutput(
            terminationStatus: process.terminationStatus, standardOutput: data, standardError: scratch.errorOutput())
    }
}

/// The child of one run, so a cancellation arriving on any thread terminates it, including one that arrives
/// before it has been launched.
private final class LaunchedProcess: Sendable {
    private let state = Mutex<(process: Process?, cancelled: Bool)>((nil, false))

    var isCancelled: Bool {
        state.withLock(\.cancelled)
    }

    func start(_ process: Process) throws {
        try process.run()
        let cancelled = state.withLock { state in
            state.process = process
            return state.cancelled
        }
        if cancelled, process.isRunning { process.terminate() }
    }

    func terminate() {
        let process = state.withLock { state in
            state.cancelled = true
            return state.process
        }
        if let process, process.isRunning { process.terminate() }
    }

    /// `SIGKILL`, for a child that ignored ``terminate()``.
    func kill() {
        let process = state.withLock(\.process)
        if let process, process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
    }
}

/// The temporary files one run reads its input from and writes its errors to.
private struct ScratchFiles: Sendable {
    private let errorFile: URL
    private let inputFile: URL?

    init(input: Data?) throws {
        let directory = FileManager.default.temporaryDirectory
        let stem = "atelier-process-\(UUID().uuidString)"
        let errorFile = directory.appending(path: stem + ".stderr")
        try Self.createPrivateFile(at: errorFile, contents: Data())
        self.errorFile = errorFile
        guard let input else {
            inputFile = nil
            return
        }
        let url = directory.appending(path: stem + ".stdin")
        do {
            try Self.createPrivateFile(at: url, contents: input)
        } catch {
            // Nothing will `remove()` a value that never returned, so the error file goes now.
            try? FileManager.default.removeItem(at: errorFile)
            throw error
        }
        inputFile = url
    }

    /// Creates the file owner-readable only and refuses an existing path or a symlink, so a shared temporary
    /// directory can neither read git's error text or stdin payload nor redirect the write.
    private static func createPrivateFile(at url: URL, contents: Data) throws {
        let descriptor = url.withUnsafeFileSystemRepresentation { path in
            path.map { open($0, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600) } ?? -1
        }
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        try handle.write(contentsOf: contents)
    }

    func errorHandle() throws -> FileHandle {
        try FileHandle(forWritingTo: errorFile)
    }

    /// The input file, or the null device so the child sees an end of file at once.
    func inputHandle() throws -> FileHandle {
        guard let inputFile else { return FileHandle.nullDevice }
        return try FileHandle(forReadingFrom: inputFile)
    }

    func errorOutput() -> Data {
        (try? Data(contentsOf: errorFile)) ?? Data()
    }

    func remove() {
        try? FileManager.default.removeItem(at: errorFile)
        if let inputFile { try? FileManager.default.removeItem(at: inputFile) }
    }
}

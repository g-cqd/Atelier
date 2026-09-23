public import AemiRuntime
import Darwin
public import Foundation
import Synchronization

/// Runs a child through `Process` with one blocking job on aemi's pool per run.
///
/// The one job reads the child's standard output and standard error together, through one kqueue, each up to the
/// spec's limit, until the child exits: it then takes what the pipes already hold and stops, so a grandchild that
/// inherited them cannot hold the run open. Standard input, when given, comes from a private temporary file, so no
/// job ever waits on another job for a pool thread, whatever the pool width. Cancelling the calling task terminates
/// the child, whether or not it has been launched yet. A spec with a timeout races the job against the runner's
/// clock, so a test drives the deadline with a virtual clock. A child that ignores the termination a timeout sends is
/// killed after ``killGracePeriod``; a cancellation only sends the termination, since a cancellation handler has no
/// clock to wait on. A child that writes past an output limit is terminated and its pipes closed under it.
///
/// Every signal goes to the process group `Process` makes the child lead, so it also reaches the grandchildren the
/// child started. A daemon that leaves the group with `setsid()` escapes it, as it escapes its terminal.
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
        let input = try spec.standardInput.map { try PrivateInput($0) }
        return try await withTaskCancellationHandler {
            let output = try await withTimeout(spec.timeout, running: running) {
                try await pool.run { try Self.launch(spec, input: input, tracking: running) }
            }
            if running.isCancelled { throw CancellationError() }
            return output
        } onCancel: {
            running.cancel()
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

    /// Starts the child and reads its two outputs until it exits, then waits for it. Blocks: runs on the pool.
    private static func launch(
        _ spec: ProcessSpec, input: PrivateInput?, tracking running: LaunchedProcess
    ) throws -> ProcessOutput {
        let process = Process()
        process.executableURL = spec.executable
        process.arguments = spec.arguments
        process.currentDirectoryURL = spec.currentDirectory
        if let variables = spec.environment.variables { process.environment = variables }
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        // `Process` hands the child its own copy of the descriptor and leaves this one open for `input` to close.
        process.standardInput =
            input.map { FileHandle(fileDescriptor: $0.descriptor, closeOnDealloc: false) } ?? FileHandle.nullDevice
        let reader = try OutputReader()
        process.terminationHandler = { _ in reader.childExited() }
        do {
            try running.start(process)
        } catch {
            // With no child holding the write ends, the reads would wait for an end of file that never comes.
            try? outputPipe.fileHandleForWriting.close()
            try? errorPipe.fileHandleForWriting.close()
            throw ProcessError.launchFailed(error.localizedDescription)
        }
        var streams = [
            OutputReader.Stream(
                .standardOutput, handle: outputPipe.fileHandleForReading, limit: spec.standardOutputLimit),
            OutputReader.Stream(.standardError, handle: errorPipe.fileHandleForReading, limit: spec.standardErrorLimit)
        ]
        let overflow: OutputReader.Stream?
        do {
            overflow = try reader.collect(&streams)
        } catch {
            running.terminate()
            process.waitUntilExit()
            throw error
        }
        if let overflow {
            // Past its limit: the child goes, and closing the pipes stops a writer that ignores the termination.
            running.terminate()
            for stream in streams where stream.isOpen { try? stream.handle.close() }
            process.waitUntilExit()
            throw ProcessError.outputLimitExceeded(overflow.kind, limit: overflow.limit)
        }
        process.waitUntilExit()
        return ProcessOutput(
            terminationStatus: process.terminationStatus, standardOutput: streams[0].data,
            standardError: streams[1].data)
    }
}

/// The child of one run, so a cancellation arriving on any thread terminates it, including one that arrives
/// before it has been launched.
private final class LaunchedProcess: Sendable {
    private struct State {
        var process: Process?
        var cancelled = false
        /// Signals due before the child was launched, sent as soon as it is.
        var terminationOwed = false
        var killOwed = false
    }

    private let state = Mutex(State())

    var isCancelled: Bool {
        state.withLock(\.cancelled)
    }

    func start(_ process: Process) throws {
        try process.run()
        let owed = state.withLock { state in
            state.process = process
            return (termination: state.terminationOwed, kill: state.killOwed)
        }
        if owed.kill {
            Self.signal(SIGKILL, to: process)
        } else if owed.termination {
            Self.signal(SIGTERM, to: process)
        }
    }

    /// The caller cancelled: `SIGTERM`, and the run throws `CancellationError`.
    func cancel() {
        let process = state.withLock { state in
            state.cancelled = true
            state.terminationOwed = true
            return state.process
        }
        if let process { Self.signal(SIGTERM, to: process) }
    }

    /// `SIGTERM`, for a child past its deadline or its output limit.
    func terminate() {
        let process = state.withLock { state in
            state.terminationOwed = true
            return state.process
        }
        if let process { Self.signal(SIGTERM, to: process) }
    }

    /// `SIGKILL`, for a child that ignored ``terminate()``.
    func kill() {
        let process = state.withLock { state in
            state.killOwed = true
            return state.process
        }
        if let process { Self.signal(SIGKILL, to: process) }
    }

    /// Sends `signal` to the group the child leads, which `Process` starts it in, so it reaches the grandchildren
    /// still in that group. A child that leads no group gets the signal alone: the runner never signals a group it
    /// may share, its own included.
    private static func signal(_ signal: Int32, to process: Process) {
        guard process.isRunning else { return }
        let identifier = process.processIdentifier
        if getpgid(identifier) == identifier {
            Darwin.kill(-identifier, signal)
        } else {
            Darwin.kill(identifier, signal)
        }
    }
}

/// One kqueue over a child's two output pipes and a user event its termination handler triggers, so one blocking
/// thread reads both pipes and learns when the child exits, whoever else holds the pipes.
private final class OutputReader: Sendable {
    /// One output: what was read from it, and whether it can still be read.
    struct Stream {
        let kind: ProcessOutput.Stream
        let handle: FileHandle
        /// Taken while the handle is open: asking a closed handle for its descriptor raises an exception.
        let descriptor: Int32
        let limit: Int
        var data = Data()
        var isOpen = true

        init(_ kind: ProcessOutput.Stream, handle: FileHandle, limit: Int) {
            self.kind = kind
            self.handle = handle
            descriptor = handle.fileDescriptor
            self.limit = limit
        }
    }

    private static let exitEvent: UInt = 1
    /// Closed on deinit: the termination handler keeps the reader alive until it has run.
    private let queue: Int32

    init() throws {
        queue = kqueue()
        guard queue >= 0 else { throw Self.failure("kqueue") }
        var exit = Self.event(Self.exitEvent, filter: EVFILT_USER, flags: EV_ADD | EV_CLEAR)
        guard kevent(queue, &exit, 1, nil, 0, nil) == 0 else {
            let error = Self.failure("kevent")
            close(queue)
            throw error
        }
    }

    deinit {
        close(queue)
    }

    /// Called from the child's termination handler, on a thread of Foundation's.
    func childExited() {
        var trigger = Self.event(Self.exitEvent, filter: EVFILT_USER, flags: 0, fflags: NOTE_TRIGGER)
        // Should the trigger fail, the reads still end with the pipes, as they did before the event existed.
        _ = kevent(queue, &trigger, 1, nil, 0, nil)
    }

    /// Reads `streams` until the child exits, then what they hold at that moment, or until both end.
    /// - Returns: The stream that passed its limit, after which nothing more is read.
    func collect(_ streams: inout [Stream]) throws -> Stream? {
        var changes = streams.map { Self.event(UInt($0.descriptor), filter: EVFILT_READ, flags: EV_ADD) }
        guard kevent(queue, &changes, Int32(changes.count), nil, 0, nil) == 0 else { throw Self.failure("kevent") }
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        var events = Array(repeating: Self.event(0, filter: 0, flags: 0), count: 4)
        var exited = false
        while !exited, streams.contains(where: \.isOpen) {
            let count = kevent(queue, nil, 0, &events, Int32(events.count), nil)
            guard count >= 0 else {
                if errno == EINTR { continue }
                throw Self.failure("kevent")
            }
            for event in events.prefix(Int(count)) {
                if event.filter == Int16(EVFILT_USER) {
                    exited = true
                } else if let overflow = take(event, from: &streams, into: &buffer) {
                    return overflow
                }
            }
        }
        guard exited else { return nil }
        // The child is gone and everything it wrote is in the pipes; whatever comes later is a grandchild's.
        var zero = timespec(tv_sec: 0, tv_nsec: 0)
        let count = kevent(queue, nil, 0, &events, Int32(events.count), &zero)
        for event in events.prefix(max(Int(count), 0)) where event.filter == Int16(EVFILT_READ) {
            if let overflow = take(event, from: &streams, into: &buffer) { return overflow }
        }
        return nil
    }

    /// Reads the bytes `event` reports ready on its stream, and closes the stream once it has ended.
    /// - Returns: The stream, when it passed its limit.
    private func take(_ event: kevent, from streams: inout [Stream], into buffer: inout [UInt8]) -> Stream? {
        guard let index = streams.firstIndex(where: { $0.isOpen && UInt($0.descriptor) == event.ident }) else {
            return nil
        }
        let descriptor = streams[index].descriptor
        var remaining = Int(event.data)
        var ended = event.flags & UInt16(EV_EOF) != 0
        while remaining > 0 {
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(descriptor, bytes.baseAddress, min(remaining, bytes.count))
            }
            if count < 0, errno == EINTR { continue }
            guard count > 0 else {
                // An end or an error where bytes were reported: nothing more will come through this pipe.
                ended = true
                break
            }
            guard streams[index].data.count + count <= streams[index].limit else { return streams[index] }
            streams[index].data.append(contentsOf: buffer[0 ..< count])
            remaining -= count
        }
        if ended {
            // Closing drops the kqueue's watch too, which would otherwise report the end forever.
            streams[index].isOpen = false
            try? streams[index].handle.close()
        }
        return nil
    }

    /// A kqueue change or event record; `kevent` also names the call, which keeps the bare initializer ambiguous.
    private static func event(_ identifier: UInt, filter: Int32, flags: Int32, fflags: Int32 = 0) -> kevent {
        kevent(
            ident: identifier, filter: Int16(filter), flags: UInt16(flags), fflags: UInt32(fflags), data: 0, udata: nil)
    }

    private static func failure(_ call: String) -> ProcessError {
        ProcessError.launchFailed("\(call): \(String(cString: strerror(errno)))")
    }
}

/// Standard input for one child: a file created owner-readable only, refusing an existing path or a symlink, then
/// unlinked at once, so nothing in the shared temporary directory can read the payload, swap the file or be read in
/// its place. The child reads it through its own copy of the descriptor this keeps.
private final class PrivateInput: Sendable {
    let descriptor: Int32

    init(_ contents: Data) throws {
        let path = FileManager.default.temporaryDirectory.appending(path: "atelier-process-\(UUID().uuidString).stdin")
        let descriptor = path.withUnsafeFileSystemRepresentation { path in
            path.map { open($0, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600) } ?? -1
        }
        guard descriptor >= 0 else { throw Self.lastError() }
        self.descriptor = descriptor
        // Unlinked before a byte is written, so a failure here leaves at most an empty file behind.
        let unlinked = path.withUnsafeFileSystemRepresentation { path in path.map { unlink($0) } ?? -1 }
        guard unlinked == 0 else { throw Self.lastError() }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        try handle.write(contentsOf: contents)
        try handle.seek(toOffset: 0)
    }

    private static func lastError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    deinit {
        close(descriptor)
    }
}

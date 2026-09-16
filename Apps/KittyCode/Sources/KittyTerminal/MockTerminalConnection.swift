import Foundation
import Synchronization

/// An in-memory `TerminalConnection` for use in tests.
///
/// `MockTerminalConnection` replaces real PTY or stdin/stdout I/O with in-memory
/// buffers, allowing tests to feed input programmatically and inspect what was written
/// without touching any file descriptor.
///
/// Mutable state is held inside a `Mutex` (Sendable), so the class needs no
/// `@unchecked` escape hatch.
public final class MockTerminalConnection: TerminalConnection {
    private struct State: Sendable {
        var inputBuffer: [UInt8] = []
        var queuedReadResults: [Result<[UInt8], TerminalError>] = []
        var outputBuffer = ContiguousArray<UInt8>()
        var isRawMode = false
        var size: TerminalSize
        var enterRawModeCallCount = 0
        var restoreModeCallCount = 0
    }

    private let state: Mutex<State>

    /// Creates a mock connection with the given initial terminal size.
    ///
    /// - Parameter size: The terminal size returned by `getSize()`. Defaults to 80 × 24.
    public init(size: TerminalSize = TerminalSize(columns: 80, rows: 24)) {
        state = Mutex(State(size: size))
    }

    // MARK: - Test Helpers

    /// Appends bytes to the internal input buffer, making them available for the next `read` call.
    ///
    /// - Parameter bytes: The bytes to enqueue as terminal input.
    public func feedInput(_ bytes: [UInt8]) {
        withStateLock { $0.inputBuffer.append(contentsOf: bytes) }
    }

    /// Enqueues a read error to be returned by the next `read(into:)` call.
    ///
    /// - Parameter error: The error that should be returned on the next read.
    public func enqueueReadError(_ error: TerminalError) {
        withStateLock { $0.queuedReadResults.append(.failure(error)) }
    }

    /// A snapshot of all bytes written to the connection since the last `clearOutput()` call.
    public var writtenOutput: [UInt8] {
        withStateLock { Array($0.outputBuffer) }
    }

    /// `true` when the connection is currently in raw mode.
    public var isRawMode: Bool {
        withStateLock { $0.isRawMode }
    }

    /// The total number of times `enterRawMode()` has been called.
    public var enterRawModeCallCount: Int {
        withStateLock { $0.enterRawModeCallCount }
    }

    /// The total number of times `restoreMode()` has been called.
    public var restoreModeCallCount: Int {
        withStateLock { $0.restoreModeCallCount }
    }

    /// Replaces the size reported by `getSize()`.
    ///
    /// - Parameter size: The new terminal size to return.
    public func setSize(_ size: TerminalSize) {
        withStateLock { $0.size = size }
    }

    /// Discards all bytes accumulated in the output buffer.
    public func clearOutput() {
        withStateLock { $0.outputBuffer.removeAll(keepingCapacity: true) }
    }

    // MARK: - TerminalConnection

    /// Drains bytes from the in-memory input buffer into `buffer`.
    ///
    /// - Parameter buffer: The destination buffer to fill.
    /// - Returns: The number of bytes copied.
    /// - Throws: `TerminalError.connectionClosed` when the input buffer is empty.
    public func read(into buffer: UnsafeMutableRawBufferPointer) throws(TerminalError) -> Int {
        let requestedCount = buffer.count
        let result = withStateLock { state -> Result<[UInt8], TerminalError> in
            if !state.queuedReadResults.isEmpty {
                return state.queuedReadResults.removeFirst()
            }

            guard !state.inputBuffer.isEmpty else {
                return .failure(.connectionClosed)
            }

            let count = min(requestedCount, state.inputBuffer.count)
            let bytes = Array(state.inputBuffer.prefix(count))
            state.inputBuffer.removeFirst(count)
            return .success(bytes)
        }
        let bytes = try result.get()
        buffer.copyBytes(from: bytes)
        return bytes.count
    }

    /// Appends `bytes` to the in-memory output buffer.
    ///
    /// - Parameter bytes: The bytes to record as terminal output.
    /// - Throws: Never; the signature matches the connection protocol.
    public func write(_ bytes: [UInt8]) throws(TerminalError) {
        withStateLock { $0.outputBuffer.append(contentsOf: bytes) }
    }

    public func writeContiguous(_ bytes: ContiguousArray<UInt8>) throws(TerminalError) {
        withStateLock { $0.outputBuffer.append(contentsOf: bytes) }
    }

    /// Marks the connection as being in raw mode and increments `enterRawModeCallCount`.
    public func enterRawMode() throws(TerminalError) {
        withStateLock {
            $0.isRawMode = true
            $0.enterRawModeCallCount += 1
        }
    }

    /// Marks the connection as no longer in raw mode and increments `restoreModeCallCount`.
    public func restoreMode() throws(TerminalError) {
        withStateLock {
            $0.isRawMode = false
            $0.restoreModeCallCount += 1
        }
    }

    /// Returns the terminal size last set via `init(size:)` or `setSize(_:)`.
    ///
    /// - Returns: The current mock terminal size.
    public func getSize() throws(TerminalError) -> TerminalSize {
        withStateLock { $0.size }
    }

    private func withStateLock<T: Sendable>(_ body: @Sendable (inout State) -> T) -> T {
        state.withLock { currentState in
            body(&currentState)
        }
    }
}

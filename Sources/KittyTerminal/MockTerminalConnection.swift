import Foundation

// SAFETY: All mutable state is guarded by `lock` (NSLock). Every public accessor
// acquires the lock before reading or writing, ensuring thread-safe access.
/// An in-memory `TerminalConnection` for use in tests.
///
/// `MockTerminalConnection` replaces real PTY or stdin/stdout I/O with in-memory
/// buffers, allowing tests to feed input programmatically and inspect what was written
/// without touching any file descriptor.
public final class MockTerminalConnection: TerminalConnection, @unchecked Sendable {
    private let lock = NSLock()
    private var inputBuffer: [UInt8] = []
    private var outputBuffer: [UInt8] = []
    private var _isRawMode = false
    private var _size: TerminalSize
    private var _enterRawModeCallCount = 0
    private var _restoreModeCallCount = 0

    /// Creates a mock connection with the given initial terminal size.
    ///
    /// - Parameter size: The terminal size returned by `getSize()`. Defaults to 80 × 24.
    public init(size: TerminalSize = TerminalSize(columns: 80, rows: 24)) {
        _size = size
    }

    // MARK: - Test Helpers

    /// Appends bytes to the internal input buffer, making them available for the next `read` call.
    ///
    /// - Parameter bytes: The bytes to enqueue as terminal input.
    public func feedInput(_ bytes: [UInt8]) {
        lock.withLock { inputBuffer.append(contentsOf: bytes) }
    }

    /// A snapshot of all bytes written to the connection since the last `clearOutput()` call.
    public var writtenOutput: [UInt8] {
        lock.withLock { outputBuffer }
    }

    /// `true` when the connection is currently in raw mode.
    public var isRawMode: Bool {
        lock.withLock { _isRawMode }
    }

    /// The total number of times `enterRawMode()` has been called.
    public var enterRawModeCallCount: Int {
        lock.withLock { _enterRawModeCallCount }
    }

    /// The total number of times `restoreMode()` has been called.
    public var restoreModeCallCount: Int {
        lock.withLock { _restoreModeCallCount }
    }

    /// Replaces the size reported by `getSize()`.
    ///
    /// - Parameter size: The new terminal size to return.
    public func setSize(_ size: TerminalSize) {
        lock.withLock { _size = size }
    }

    /// Discards all bytes accumulated in the output buffer.
    public func clearOutput() {
        lock.withLock { outputBuffer.removeAll() }
    }

    // MARK: - TerminalConnection

    /// Drains bytes from the in-memory input buffer into `buffer`.
    ///
    /// - Parameter buffer: The destination buffer to fill.
    /// - Returns: The number of bytes copied.
    /// - Throws: `TerminalError.connectionClosed` when the input buffer is empty.
    public func read(into buffer: UnsafeMutableRawBufferPointer) throws(TerminalError) -> Int {
        lock.lock()
        guard !inputBuffer.isEmpty else {
            lock.unlock()
            throw .connectionClosed
        }
        let count = min(buffer.count, inputBuffer.count)
        for i in 0..<count {
            buffer[i] = inputBuffer[i]
        }
        inputBuffer.removeFirst(count)
        lock.unlock()
        return count
    }

    /// Appends `bytes` to the in-memory output buffer.
    ///
    /// - Parameter bytes: The bytes to record as terminal output.
    public func write(_ bytes: [UInt8]) throws(TerminalError) {
        lock.withLock { outputBuffer.append(contentsOf: bytes) }
    }

    /// Marks the connection as being in raw mode and increments `enterRawModeCallCount`.
    public func enterRawMode() throws(TerminalError) {
        lock.withLock {
            _isRawMode = true
            _enterRawModeCallCount += 1
        }
    }

    /// Marks the connection as no longer in raw mode and increments `restoreModeCallCount`.
    public func restoreMode() throws(TerminalError) {
        lock.withLock {
            _isRawMode = false
            _restoreModeCallCount += 1
        }
    }

    /// Returns the terminal size last set via `init(size:)` or `setSize(_:)`.
    ///
    /// - Returns: The current mock terminal size.
    public func getSize() throws(TerminalError) -> TerminalSize {
        lock.withLock { _size }
    }
}

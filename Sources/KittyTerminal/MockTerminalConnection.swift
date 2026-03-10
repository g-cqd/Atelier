import Foundation

public final class MockTerminalConnection: TerminalConnection, @unchecked Sendable {
    private let lock = NSLock()
    private var inputBuffer: [UInt8] = []
    private var outputBuffer: [UInt8] = []
    private var _isRawMode = false
    private var _size: TerminalSize
    private var _enterRawModeCallCount = 0
    private var _restoreModeCallCount = 0

    public init(size: TerminalSize = TerminalSize(columns: 80, rows: 24)) {
        _size = size
    }

    // MARK: - Test Helpers

    public func feedInput(_ bytes: [UInt8]) {
        lock.withLock { inputBuffer.append(contentsOf: bytes) }
    }

    public var writtenOutput: [UInt8] {
        lock.withLock { outputBuffer }
    }

    public var isRawMode: Bool {
        lock.withLock { _isRawMode }
    }

    public var enterRawModeCallCount: Int {
        lock.withLock { _enterRawModeCallCount }
    }

    public var restoreModeCallCount: Int {
        lock.withLock { _restoreModeCallCount }
    }

    public func setSize(_ size: TerminalSize) {
        lock.withLock { _size = size }
    }

    public func clearOutput() {
        lock.withLock { outputBuffer.removeAll() }
    }

    // MARK: - TerminalConnection

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

    public func write(_ bytes: [UInt8]) throws(TerminalError) {
        lock.withLock { outputBuffer.append(contentsOf: bytes) }
    }

    public func enterRawMode() throws(TerminalError) {
        lock.withLock {
            _isRawMode = true
            _enterRawModeCallCount += 1
        }
    }

    public func restoreMode() throws(TerminalError) {
        lock.withLock {
            _isRawMode = false
            _restoreModeCallCount += 1
        }
    }

    public func getSize() throws(TerminalError) -> TerminalSize {
        lock.withLock { _size }
    }
}

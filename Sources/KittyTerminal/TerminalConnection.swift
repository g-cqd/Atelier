/// A low-level, bidirectional connection to a terminal device.
///
/// Conforming types provide byte-level I/O and terminal control operations.
/// All conformances must also conform to `Sendable` to allow safe cross-isolation use.
public protocol TerminalConnection: Sendable {
    /// Reads available bytes from the terminal into the given buffer.
    ///
    /// - Parameter buffer: The destination buffer to fill with incoming bytes.
    /// - Returns: The number of bytes actually read.
    /// - Throws: `TerminalError.readFailed` if the read syscall fails, or
    ///   `TerminalError.connectionClosed` if the connection is at end-of-file.
    func read(into buffer: UnsafeMutableRawBufferPointer) throws(TerminalError) -> Int

    /// Writes all bytes to the terminal.
    ///
    /// - Parameter bytes: The bytes to transmit.
    /// - Throws: `TerminalError.writeFailed` if the write syscall fails.
    func write(_ bytes: [UInt8]) throws(TerminalError)

    /// Writes all bytes from a ContiguousArray to the terminal (zero-copy path).
    ///
    /// Default implementation bridges to `write(_:)`. Conforming types may override
    /// for zero-copy writes using `withUnsafeBufferPointer`.
    ///
    /// - Parameter bytes: The contiguous byte buffer to transmit.
    /// - Throws: `TerminalError.writeFailed` if the write syscall fails.
    func writeContiguous(_ bytes: ContiguousArray<UInt8>) throws(TerminalError)

    /// Switches the terminal into raw (non-canonical) mode.
    ///
    /// In raw mode, input is forwarded byte-by-byte with no line buffering,
    /// echo, or signal processing.
    /// - Throws: `TerminalError.notATerminal` if the file descriptor is not a tty,
    ///   `TerminalError.alreadyInRawMode` if raw mode is already active, or
    ///   `TerminalError.failedToEnterRawMode` on a syscall failure.
    func enterRawMode() throws(TerminalError)

    /// Restores the terminal to the mode that was active before `enterRawMode()`.
    ///
    /// - Throws: `TerminalError.failedToRestoreTerminal` if the syscall fails.
    func restoreMode() throws(TerminalError)

    /// Returns the current dimensions of the terminal window.
    ///
    /// - Returns: A `TerminalSize` value describing the terminal's column and row counts.
    /// - Throws: `TerminalError.failedToGetSize` if the size cannot be determined.
    func getSize() throws(TerminalError) -> TerminalSize
}

// Default implementation bridges ContiguousArray to Array
extension TerminalConnection {
    public func writeContiguous(_ bytes: ContiguousArray<UInt8>) throws(TerminalError) {
        try write(Array(bytes))
    }
}

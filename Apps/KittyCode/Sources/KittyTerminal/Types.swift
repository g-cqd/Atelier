// MARK: - Terminal Size

/// The dimensions of a terminal window, expressed in character cells and optional pixels.
public struct TerminalSize: Sendable, Equatable {
    /// The number of character columns in the terminal window.
    public var columns: Int

    /// The number of character rows in the terminal window.
    public var rows: Int

    /// The pixel width of the terminal window, or `0` when unavailable.
    public var pixelWidth: Int

    /// The pixel height of the terminal window, or `0` when unavailable.
    public var pixelHeight: Int

    /// Creates a terminal size with the given dimensions.
    ///
    /// - Parameters:
    ///   - columns: The number of character columns.
    ///   - rows: The number of character rows.
    ///   - pixelWidth: The pixel width of the window. Defaults to `0`.
    ///   - pixelHeight: The pixel height of the window. Defaults to `0`.
    public init(columns: Int, rows: Int, pixelWidth: Int = 0, pixelHeight: Int = 0) {
        self.columns = columns
        self.rows = rows
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

// MARK: - Terminal Error

/// Errors that can occur during terminal I/O and control operations.
public enum TerminalError: Error, Sendable, Equatable {
    /// The file descriptor does not refer to a terminal device.
    case notATerminal

    /// The terminal could not be switched into raw mode.
    case failedToEnterRawMode

    /// The terminal could not be restored to its previous mode.
    case failedToRestoreTerminal

    /// The terminal window size could not be determined.
    case failedToGetSize

    /// A read syscall failed. The associated value is the `errno` code.
    case readFailed(Int32)

    /// A write syscall failed. The associated value is the `errno` code.
    case writeFailed(Int32)

    /// An attempt was made to enter raw mode when it is already active.
    case alreadyInRawMode

    /// The terminal connection reached end-of-file or was closed by the peer.
    case connectionClosed
}

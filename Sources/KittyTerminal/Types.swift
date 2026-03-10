// MARK: - Terminal Size

public struct TerminalSize: Sendable, Equatable {
    public var columns: Int
    public var rows: Int
    public var pixelWidth: Int
    public var pixelHeight: Int

    public init(columns: Int, rows: Int, pixelWidth: Int = 0, pixelHeight: Int = 0) {
        self.columns = columns
        self.rows = rows
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

// MARK: - Terminal Error

public enum TerminalError: Error, Sendable, Equatable {
    case notATerminal
    case failedToEnterRawMode
    case failedToRestoreTerminal
    case failedToGetSize
    case readFailed(Int32)
    case writeFailed(Int32)
    case alreadyInRawMode
    case connectionClosed
}

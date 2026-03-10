public struct RawModeGuard: ~Copyable, Sendable {
    private let connection: any TerminalConnection

    public init(connection: any TerminalConnection) throws(TerminalError) {
        self.connection = connection
        try connection.enterRawMode()
    }

    deinit {
        try? connection.restoreMode()
    }
}

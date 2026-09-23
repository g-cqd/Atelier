public struct RawModeGuard: ~Copyable, Sendable {
    private let connection: any TerminalConnection

    public init(connection: any TerminalConnection) throws(TerminalError) {
        self.connection = connection
        try connection.enterRawMode()
    }

    deinit {
        // A deinit can't propagate a failed restore, so it is logged as a fault; the tty stays scrambled until `reset`.
        do {
            try connection.restoreMode()
        } catch {
            KittyLogger.fault(public: "RawModeGuard: tcsetattr restore failed; tty may be scrambled")
        }
    }
}

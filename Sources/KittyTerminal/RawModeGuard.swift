public struct RawModeGuard: ~Copyable, Sendable {
    private let connection: any TerminalConnection

    public init(connection: any TerminalConnection) throws(TerminalError) {
        self.connection = connection
        try connection.enterRawMode()
    }

    deinit {
        // The terminal must be left in a usable state. If `tcsetattr` fails we
        // can't propagate the error from a deinit, so log at .fault level: the
        // user will be staring at a scrambled tty until they `reset` manually.
        do {
            try connection.restoreMode()
        } catch {
            KittyLogger.fault(public: "RawModeGuard: tcsetattr restore failed; tty may be scrambled")
        }
    }
}

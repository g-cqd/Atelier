import os

/// Structured logger for macOS runtime diagnostics.
///
/// Uses `os.Logger` for integration with Console.app and Instruments.
public enum KittyLogger: Sendable {
    private static let osLogger = Logger(subsystem: "com.kittytui", category: "runtime")

    /// Logs a message at the error level.
    ///
    /// - Parameter message: A human-readable description of the error condition.
    public static func error(_ message: String) {
        osLogger.error("\(message, privacy: .public)")
    }

    /// Logs a message at the warning level.
    ///
    /// - Parameter message: A human-readable description of the warning condition.
    public static func warning(_ message: String) {
        osLogger.warning("\(message, privacy: .public)")
    }

    /// Logs a message at the debug level.
    ///
    /// Debug messages are stripped from release builds.
    /// - Parameter message: A human-readable diagnostic message.
    public static func debug(_ message: String) {
        osLogger.debug("\(message, privacy: .public)")
    }
}

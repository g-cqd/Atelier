#if canImport(os)
import os
#endif
import Foundation

/// Cross-platform structured logger.
///
/// Uses `os.Logger` on Apple platforms for integration with Console.app
/// and Instruments. Falls back to stderr on Linux.
public enum KittyLogger: Sendable {
    #if canImport(os)
    private static let osLogger = Logger(subsystem: "com.kittytui", category: "runtime")
    #endif

    /// Logs a message at the error level.
    ///
    /// - Parameter message: A human-readable description of the error condition.
    public static func error(_ message: String) {
        #if canImport(os)
        osLogger.error("\(message, privacy: .public)")
        #else
        fputs("[ERROR] \(message)\n", stderr)
        #endif
    }

    /// Logs a message at the warning level.
    ///
    /// - Parameter message: A human-readable description of the warning condition.
    public static func warning(_ message: String) {
        #if canImport(os)
        osLogger.warning("\(message, privacy: .public)")
        #else
        fputs("[WARN] \(message)\n", stderr)
        #endif
    }

    /// Logs a message at the debug level.
    ///
    /// Debug messages are stripped from release builds on Apple platforms.
    /// - Parameter message: A human-readable diagnostic message.
    public static func debug(_ message: String) {
        #if canImport(os)
        osLogger.debug("\(message, privacy: .public)")
        #else
        fputs("[DEBUG] \(message)\n", stderr)
        #endif
    }
}

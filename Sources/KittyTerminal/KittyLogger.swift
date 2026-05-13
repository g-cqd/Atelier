import Foundation
import os

/// Structured logger for macOS runtime diagnostics.
///
/// Uses `os.Logger` for integration with Console.app and Instruments.
///
/// Dynamic message contents are redacted by default — callers that interpolate
/// untrusted values (file paths, error descriptions, user input) get safe
/// behaviour automatically. Use the `public:` variants to mark contents that
/// are known to contain no sensitive data (e.g. static literals or enum cases).
public enum KittyLogger: Sendable {
    private static let osLogger = Logger(subsystem: "com.kittytui", category: "runtime")

    public static func fault(_ message: String) {
        osLogger.fault("\(message, privacy: .private)")
    }

    public static func error(_ message: String) {
        osLogger.error("\(message, privacy: .private)")
    }

    public static func warning(_ message: String) {
        osLogger.warning("\(message, privacy: .private)")
    }

    public static func debug(_ message: String) {
        osLogger.debug("\(message, privacy: .private)")
    }

    /// Logs `message` at the fault level without redaction. Use only for
    /// content that contains no sensitive data (static literals, enum cases).
    public static func fault(public message: String) {
        osLogger.fault("\(message, privacy: .public)")
    }

    /// Logs `message` at the error level without redaction. Use only for
    /// content that contains no sensitive data (static literals, enum cases).
    public static func error(public message: String) {
        osLogger.error("\(message, privacy: .public)")
    }

    /// Logs `message` at the warning level without redaction.
    public static func warning(public message: String) {
        osLogger.warning("\(message, privacy: .public)")
    }

    /// Logs `message` at the debug level without redaction.
    public static func debug(public message: String) {
        osLogger.debug("\(message, privacy: .public)")
    }

    /// Logs at `.error` AND writes to stderr. Use for CLI parse failures and
    /// terminal-mode crash reports — the user expects to see them in their
    /// shell, while Console.app and Instruments captures them via the unified
    /// logging system.
    public static func stderr(_ message: String) {
        osLogger.error("\(message, privacy: .private)")
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}

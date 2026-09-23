import Foundation
import os

/// Runtime diagnostics through `os.Logger`. Messages are redacted by default; the `public:` variants are only for
/// contents known to hold no sensitive data, such as static literals or enum cases.
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

    /// Logs `message` at the fault level without redaction.
    public static func fault(public message: String) {
        osLogger.fault("\(message, privacy: .public)")
    }

    /// Logs `message` at the error level without redaction.
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

    /// Logs `message` redacted at the error level and writes it in full to stderr, for the user's shell.
    public static func stderr(_ message: String) {
        osLogger.error("\(message, privacy: .private)")
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}

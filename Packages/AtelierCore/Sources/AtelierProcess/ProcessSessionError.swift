public import Foundation

/// Why a ``ProcessSession`` operation failed.
public enum ProcessSessionError: Error, Sendable {
    /// The session was never started, or ``ProcessSession/start()`` had not yet reached a running child.
    case notRunning
    /// The child could not be spawned; the message comes from swift-subprocess.
    case launchFailed(String)
    /// The child had already exited when the operation was attempted.
    case exited(status: Int32, stderrTail: Data)
    /// A write to the child's standard input failed while it was running.
    case writeFailed(String)
}

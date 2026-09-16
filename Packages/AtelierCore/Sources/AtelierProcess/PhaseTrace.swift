import AemiRuntime
import Foundation

/// Millisecond timeline of the pipeline on stderr, enabled with the `ATELIER_TRACE` (or `GDV_TRACE`) environment variable.
public enum PhaseTrace {
    private static let start = LiveClock.monotonicNanoseconds()
    public static let isEnabled =
        ProcessInfo.processInfo.environment["ATELIER_TRACE"] != nil
        || ProcessInfo.processInfo.environment["GDV_TRACE"] != nil

    public static func log(_ event: @autoclosure () -> String) {
        guard isEnabled else { return }
        let milliseconds = Double(LiveClock.monotonicNanoseconds() - start) / 1e6
        FileHandle.standardError.write(Data("[\(String(format: "%8.1f", milliseconds)) ms] \(event())\n".utf8))
    }
}

import AemiRuntime
import DiffCore
import Foundation

/// Millisecond timeline of the pipeline on stderr, enabled with the `GDV_TRACE` environment variable.
package enum PhaseTrace {
    private static let start = LiveClock.monotonicNanoseconds()
    package static let isEnabled = ProcessInfo.processInfo.environment["GDV_TRACE"] != nil

    package static func log(_ event: @autoclosure () -> String) {
        guard isEnabled else { return }
        let milliseconds = Double(LiveClock.monotonicNanoseconds() - start) / 1e6
        FileHandle.standardError.write(Data("[\(String(format: "%8.1f", milliseconds)) ms] \(event())\n".utf8))
    }
}

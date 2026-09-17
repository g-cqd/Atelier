import Foundation
import os

/// Bounds native regex matching at Foundation's progress callbacks, including within one match.
enum RegexMatcher {
    private static let logger = Logger(subsystem: "com.kittytui.search", category: "regex")

    /// What one file's regex pass may spend before the remaining lines are skipped.
    static let fileBudget: Duration = .milliseconds(500)

    /// Enumerates matches until completion, cancellation, `deadline`, or a false callback result.
    /// - Note: Foundation controls callback frequency; the budget is cooperative, not a hard deadline.
    static func enumerate(
        _ regex: NSRegularExpression,
        in text: String,
        deadline: ContinuousClock.Instant,
        body: (NSTextCheckingResult) -> Bool
    ) {
        guard !Task.isCancelled, ContinuousClock.now < deadline else { return }
        regex.enumerateMatches(
            in: text, options: [.reportProgress, .reportCompletion],
            range: NSRange(text.startIndex ..< text.endIndex, in: text)
        ) { result, flags, stop in
            // Foundation owns this pointer for the synchronous callback; it never escapes.
            if Task.isCancelled {
                stop.pointee = true
            } else if flags.contains(.internalError) {
                logger.error("Regular expression matching failed inside Foundation")
                stop.pointee = true
            } else if ContinuousClock.now >= deadline {
                logger.warning("Regular expression exceeded its time budget; remaining matches skipped")
                stop.pointee = true
            } else if let result, !body(result) {
                stop.pointee = true
            }
        }
    }
}

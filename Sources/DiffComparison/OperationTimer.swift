import DiffCore
import DiffGit
package import DiffRendering
import Foundation
import Observation

/// Times one operation, from the change that started it to its render and to its first appearance on screen.
package struct OperationTimer {
    private let uptime: @Sendable () -> Duration
    private var start: Duration?
    private var isComplete = true
    /// The render whose first appearance on screen ends the first-display measurement.
    package private(set) var pendingDisplayID: RenderedDiff.ID?
    package private(set) var timing = RenderTiming()

    package init(uptime: @escaping @Sendable () -> Duration) {
        self.uptime = uptime
    }

    package var isInFlight: Bool { start != nil && !isComplete }

    /// Starts timing; an operation in flight is kept when `onlyIfIdle` is set, so a whole comparison counts from
    /// the source change that began it.
    package mutating func begin(onlyIfIdle: Bool = false) {
        if onlyIfIdle, isInFlight { return }
        start = uptime()
        isComplete = false
        pendingDisplayID = nil
        timing = RenderTiming()
    }

    /// Stops timing without a result, for re-layouts that are not operations of their own.
    package mutating func abandon() {
        start = nil
        pendingDisplayID = nil
    }

    package mutating func awaitDisplay(of id: RenderedDiff.ID) {
        if start != nil { pendingDisplayID = id }
    }

    package mutating func finish() {
        guard let start, !isComplete else { return }
        isComplete = true
        timing.rendered = uptime() - start
    }

    /// The elapsed time when `id` is the awaited render, nil otherwise.
    package mutating func displayed(_ id: RenderedDiff.ID) -> Duration? {
        guard pendingDisplayID == id, let start else { return nil }
        pendingDisplayID = nil
        return uptime() - start
    }

    package mutating func record(firstDisplay: Duration) {
        timing.firstDisplay = firstDisplay
    }
}

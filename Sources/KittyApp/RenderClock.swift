public import Observation

/// Observation-aware tick source for the render loop.
///
/// `RenderClock` is `@Observable` so any consumer wrapped in
/// `withObservationTracking` is notified when the tick advances. Editor
/// state's dirty markers call `advance()` whenever a repaint is warranted;
/// a separate listener task in the app runtime then drives an
/// `InputEvent.refresh` injection so the existing event loop wakes and
/// renders.
///
/// This complements (and over time replaces) the manual
/// `RenderRefreshSource.invalidate()` callsite pattern: instead of every
/// mutator remembering to call `invalidate`, the dirty marker that already
/// runs on each mutation advances the clock, and observation propagates
/// the wake.
@Observable
@MainActor
public final class RenderClock {
    public private(set) var tick: UInt64 = 0

    public init() {}

    /// Bumps the tick counter. Any active `withObservationTracking { _ = clock.tick }`
    /// session fires its `onChange` callback exactly once for a synchronous
    /// burst of `advance()` calls — natural coalescing for back-to-back
    /// mutations inside one main-actor entry.
    public func advance() {
        tick &+= 1
    }
}

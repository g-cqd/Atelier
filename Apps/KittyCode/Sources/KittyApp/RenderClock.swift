public import Observation

/// The render loop's observable tick: a dirty marker calls `advance()`, and the runtime's observer then injects
/// `InputEvent.refresh` so the event loop wakes and renders.
@Observable
@MainActor
public final class RenderClock {
    public private(set) var tick: UInt64 = 0

    public init() {}

    /// Bumps the tick. An observer's `onChange` fires once for a synchronous burst of calls, which coalesces them.
    public func advance() {
        tick &+= 1
    }
}

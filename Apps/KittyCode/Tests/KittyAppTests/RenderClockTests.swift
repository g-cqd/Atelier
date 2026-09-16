import Observation
import Synchronization
import Testing

@testable import KittyApp

@Suite
@MainActor
struct RenderClockTests {
    @Test
    func `advance increments tick`() {
        let clock = RenderClock()
        let before = clock.tick
        clock.advance()
        #expect(clock.tick == before &+ 1)
    }

    @Test
    func `observation tracking fires onChange after advance`() async {
        let clock = RenderClock()
        let fireCount = Mutex<Int>(0)
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            withObservationTracking {
                _ = clock.tick
            } onChange: {
                fireCount.withLock { $0 &+= 1 }
                cont.resume()
            }
            Task { @MainActor in
                clock.advance()
            }
        }
        #expect(fireCount.withLock { $0 } == 1)
    }

    @Test
    func `multiple synchronous advances coalesce into one onChange`() async {
        let clock = RenderClock()
        let fireCount = Mutex<Int>(0)
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            withObservationTracking {
                _ = clock.tick
            } onChange: {
                fireCount.withLock { $0 &+= 1 }
                cont.resume()
            }
            Task { @MainActor in
                // Three sync mutations in the same main-actor entry; onChange
                // fires exactly once for the burst — the natural coalescing
                // that lets dirty markers update freely without flooding
                // the render scheduler.
                clock.advance()
                clock.advance()
                clock.advance()
            }
        }
        #expect(fireCount.withLock { $0 } == 1)
        #expect(clock.tick >= 3)
    }
}

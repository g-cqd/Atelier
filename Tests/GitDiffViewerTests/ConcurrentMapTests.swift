import DiffConcurrency
import DiffTestSupport
import Synchronization
import Testing

struct ConcurrentMapTests {
    @Test
    func `results keep the input order whatever the completion order`() async throws {
        let results = try await mapConcurrently(Array(0..<50), limit: 8) { value in
            try await Task.sleep(for: .microseconds(UInt64(50 - value) * 10))
            return value * 2
        }
        #expect(results == (0..<50).map { $0 * 2 })
    }

    @Test
    func `never more than the limit runs at once`() async throws {
        let inFlight = Atomic(0)
        let peak = Atomic(0)
        _ = try await mapConcurrently(Array(0..<40), limit: 4) { _ in
            let current = inFlight.add(1, ordering: .relaxed).newValue
            var seen = peak.load(ordering: .relaxed)
            while seen < current, !peak.compareExchange(expected: seen, desired: current, ordering: .relaxed).exchanged {
                seen = peak.load(ordering: .relaxed)
            }
            try await Task.sleep(for: .milliseconds(2))
            inFlight.subtract(1, ordering: .relaxed)
        }
        #expect(peak.load(ordering: .relaxed) <= 4)
        #expect(peak.load(ordering: .relaxed) >= 2)
    }

    @Test
    func `an error stops the whole map`() async {
        struct Failure: Error {}
        await #expect(throws: Failure.self) {
            try await mapConcurrently([1, 2, 3], limit: 2) { value in
                if value == 2 { throw Failure() }
                return value
            }
        }
    }

    @Test
    func `an empty input yields an empty result`() async throws {
        let results: [Int] = try await mapConcurrently([Int](), limit: 3) { $0 }
        #expect(results.isEmpty)
    }
}

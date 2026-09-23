import AemiTesting
import Testing

/// The failure bound on the waits a test awaits: a wait that never ends fails its test, naming what it waited for,
/// instead of hanging the run. The bounds here are short on purpose; nothing is timed.
struct BoundedWaitsTests {
    @Test
    func `a wait that never ends fails with a timeout naming what it waited for`() async throws {
        let silent = AsyncProbe<Void>()

        let timeout = await #expect(throws: WaitTimeout.self) {
            try await withFailureBound(awaiting: "The silent probe", bound: .milliseconds(10)) {
                try await silent.next()
            }
        }

        #expect(timeout?.awaited == "The silent probe")
        #expect(timeout?.description.contains("BoundedWaitsTests.swift") == true)
    }

    @Test
    func `a wait that ignores cancellation fails at its bound all the same`() async throws {
        let release = AsyncProbe<Void>()
        let stuck = Task { _ = try? await release.next() }

        // Awaiting another task's value cannot be cancelled: only `release` ends this wait.
        await #expect(throws: WaitTimeout.self) {
            try await withFailureBound(awaiting: "The stuck task", bound: .milliseconds(10)) {
                await stuck.value
            }
        }

        release.send(())
        await stuck.value
    }

    @Test
    func `a wait that ends within its bound returns what it waited for`() async throws {
        let probe = AsyncProbe<Int>()
        probe.send(7)

        #expect(try await probe.expectNext() == 7)
    }
}

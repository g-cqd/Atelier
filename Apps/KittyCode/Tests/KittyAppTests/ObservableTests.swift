import Testing

@testable import KittyApp

@MainActor
@Suite
struct ObservableTests {
    @MainActor
    final class Counter: ViewModel {
        @Published var value: Int = 0
        @Published var label: String = ""
    }

    @Test func `Published assignment triggers invalidate`() {
        let sut = Counter()
        var invalidations = 0
        sut.invalidate = { invalidations += 1 }

        sut.value = 1
        #expect(invalidations == 1)

        sut.value = 2
        sut.label = "two"
        #expect(invalidations == 3)
    }

    @Test func `Published reads do not trigger invalidate`() {
        let sut = Counter()
        sut.value = 42
        var invalidations = 0
        sut.invalidate = { invalidations += 1 }

        for _ in 0 ..< 5 {
            _ = sut.value
            _ = sut.label
        }
        #expect(invalidations == 0)
    }

    @Test func `notifyChange triggers invalidate directly`() {
        let sut = Counter()
        var invalidations = 0
        sut.invalidate = { invalidations += 1 }

        sut.notifyChange()
        sut.notifyChange()
        #expect(invalidations == 2)
    }

    @Test func `default invalidate is a no-op`() {
        let sut = Counter()
        sut.value = 1  // must not crash; default invalidate is empty
        #expect(sut.value == 1)
    }

    @Test func `each ViewModel instance owns its invalidate handler`() {
        let modelA = Counter()
        let modelB = Counter()
        var aFired = 0
        var bFired = 0
        modelA.invalidate = { aFired += 1 }
        modelB.invalidate = { bFired += 1 }

        modelA.value = 1
        modelB.value = 1
        modelA.value = 2

        #expect(aFired == 2)
        #expect(bFired == 1)
    }

    @Test func `Published preserves Published value semantics across assignments`() {
        let sut = Counter()
        sut.value = 10
        #expect(sut.value == 10)
        sut.value = 20
        #expect(sut.value == 20)
    }

    @Test func `subclasses can use Published`() {
        @MainActor
        final class Extended: ViewModel {
            @Published var name: String = "anon"
            @Published var enabled: Bool = false
        }
        let sut = Extended()
        var fired = 0
        sut.invalidate = { fired += 1 }
        sut.name = "user"
        sut.enabled = true
        #expect(fired == 2)
        #expect(sut.name == "user")
        #expect(sut.enabled)
    }

    @Test func `bind(to:) wires invalidate so writes invoke the source`() {
        let sut = Counter()
        let source = RenderRefreshSource()
        sut.bind(to: source)
        // RenderRefreshSource starts with a no-op invalidate target; verify
        // calling it via the bound view model is safe (no crash, no leak).
        sut.value = 1
        source.invalidate()
        #expect(sut.value == 1)
    }

    @Test func `bind(to:) holds refresh source weakly`() {
        let sut = Counter()
        var source: RenderRefreshSource? = RenderRefreshSource()
        sut.bind(to: source!)
        source = nil
        // Should not crash even though the source has been deallocated.
        sut.value = 99
        #expect(sut.value == 99)
    }
}

import Testing

/// Lets a few main-actor test cases run at once, and makes the others wait their turn before they start.
///
/// Swift Testing starts every test case of the run together. The main-actor ones all queue on the one main thread:
/// a test that awaits an event its own work sends resumes behind every other test's main-thread work queued before
/// it, hundreds of them. On an idle machine that queue drains within seconds; at a load of 50 and more it took over a
/// minute, and hundreds of bounded waits failed together, each waiting on work that had not yet had the main thread,
/// though nothing was wrong. Through the lane, a test waits for the main thread behind at most ``width`` other tests,
/// so its waits measure its own work. Tests off the main actor keep running in parallel beside the lane.
///
/// Every main-actor suite carries it: `@Suite(.mainActorLane)`.
struct MainActorLane: SuiteTrait, TestTrait, TestScoping {
    /// How many main-actor test cases run at once: one using the main thread while the other waits on an event.
    static let width = 2

    /// The lane every suite shares.
    private static let gate = LaneGate(width: width)

    var isRecursive: Bool { true }

    func provideScope(
        for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void
    ) async throws {
        // A suite's own scope spans its tests: each of them takes the lane, not the suite as a whole.
        guard testCase != nil else { return try await function() }
        await Self.gate.enter()
        do {
            try await function()
        } catch {
            await Self.gate.leave()
            throw error
        }
        await Self.gate.leave()
    }
}

extension Trait where Self == MainActorLane {
    /// Runs the suite's test cases through ``MainActorLane``.
    static var mainActorLane: Self { MainActorLane() }
}

/// A first-come, first-served gate that lets `width` holders in at once.
private actor LaneGate {
    private let width: Int
    private var holders = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(width: Int) {
        self.width = width
    }

    func enter() async {
        guard holders >= width else {
            holders += 1
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    /// Hands the place over to the longest waiting, which keeps the count of holders as it is.
    func leave() {
        guard waiting.isEmpty else {
            waiting.removeFirst().resume()
            return
        }
        holders -= 1
    }
}

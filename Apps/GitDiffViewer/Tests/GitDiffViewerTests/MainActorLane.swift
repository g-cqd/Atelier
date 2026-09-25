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
/// Every main-actor suite carries it: `@Suite(.mainActorLane)`. A suite that fails a test running past a time limit
/// takes the lane's own, `.mainActorLane(timeLimit:)`, in place of `.timeLimit`, which counts from the test's start,
/// the turn it waits for in the lane included: under load, whole suites ran past a minute waiting for their turn.
struct MainActorLane: SuiteTrait, TestTrait, TestScoping {
    /// How many main-actor test cases run at once: one using the main thread while the other waits on an event.
    static let width = 2

    /// The lane every suite shares.
    private static let gate = LaneGate(width: width)

    /// How long a test case may run once in the lane before it fails; nil for no limit.
    var timeLimit: Duration?

    var isRecursive: Bool { true }

    func provideScope(
        for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void
    ) async throws {
        // A suite's own scope spans its tests: each of them takes the lane, not the suite as a whole.
        guard testCase != nil else { return try await function() }
        await Self.gate.enter()
        do {
            if let timeLimit {
                try await Self.run(function, within: timeLimit)
            } else {
                try await function()
            }
        } catch {
            await Self.gate.leave()
            throw error
        }
        await Self.gate.leave()
    }
}

extension MainActorLane {
    /// A test case that ran past its time limit in the lane.
    struct TimeLimitExceeded: Error, CustomStringConvertible {
        let limit: Duration
        var description: String { "The test ran past its limit of \(limit) in the main-actor lane" }
    }

    /// Runs `function`, and fails with ``TimeLimitExceeded`` once `limit` has passed, cancelling it: its bounded waits
    /// unwind on cancellation. The group waits for `function` to end before returning, so it never outlives the call.
    private static func run(_ function: @Sendable () async throws -> Void, within limit: Duration) async throws {
        try await withoutActuallyEscaping(function) { function in
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await function() }
                group.addTask {
                    try await Task.sleep(for: limit)
                    throw TimeLimitExceeded(limit: limit)
                }
                defer { group.cancelAll() }
                try await group.next()
            }
        }
    }
}

extension Trait where Self == MainActorLane {
    /// Runs the suite's test cases through ``MainActorLane``.
    static var mainActorLane: Self { MainActorLane() }

    /// Runs the suite's test cases through ``MainActorLane``, each failing once it has run for `timeLimit` in it.
    static func mainActorLane(timeLimit: Duration) -> Self { MainActorLane(timeLimit: timeLimit) }
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

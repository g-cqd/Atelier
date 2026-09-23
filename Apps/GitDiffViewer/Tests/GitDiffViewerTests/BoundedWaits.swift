import AemiTesting
import Synchronization
import Testing

/// A wait that got nothing within its failure bound: what it waited for, and the line that waited.
struct WaitTimeout: Error, CustomStringConvertible {
    let awaited: String
    let bound: Duration
    let sourceLocation: SourceLocation

    var description: String {
        "\(awaited) did not come within \(bound), awaited at \(sourceLocation.fileID):\(sourceLocation.line)"
    }
}

/// Returns what `wait` returns, or throws ``WaitTimeout`` naming `awaited` once `bound` of real time has passed.
///
/// The wait runs in a task of its own, which the bound cancels and leaves to unwind rather than awaits: a wait that
/// ignores cancellation still fails its test instead of hanging the run. Cancelling the caller cancels the wait.
func withFailureBound<Value: Sendable>(
    awaiting awaited: String, bound: Duration = TaskProviderSpy.failureBound,
    sourceLocation: SourceLocation = #_sourceLocation, _ wait: @escaping @Sendable () async throws -> Value
) async throws -> Value {
    let outcome = FirstOutcome<Value>()
    let waiter = Task {
        do {
            outcome.settle(.success(try await wait()))
        } catch {
            outcome.settle(.failure(error))
        }
    }
    let timer = Task {
        guard (try? await Task.sleep(for: bound)) != nil else { return }
        outcome.settle(.failure(WaitTimeout(awaited: awaited, bound: bound, sourceLocation: sourceLocation)))
    }
    defer {
        waiter.cancel()
        timer.cancel()
    }
    return try await withTaskCancellationHandler {
        try await outcome.value
    } onCancel: {
        waiter.cancel()
    }
}

/// The first result a wait or its failure bound reports, handed to the one caller awaiting it.
private final class FirstOutcome<Value: Sendable>: Sendable {
    private enum State {
        case pending(CheckedContinuation<Value, any Error>?)
        case settled(Result<Value, any Error>)
    }

    private let state = Mutex(State.pending(nil))

    /// Keeps `result` unless another one came first, and resumes the caller awaiting it.
    func settle(_ result: Result<Value, any Error>) {
        let awaiting: CheckedContinuation<Value, any Error>? = state.withLock { state in
            guard case .pending(let continuation) = state else { return nil }
            state = .settled(result)
            return continuation
        }
        awaiting?.resume(with: result)
    }

    /// The first result, once there is one.
    var value: Value {
        get async throws {
            try await withCheckedThrowingContinuation { continuation in
                let settled: Result<Value, any Error>? = state.withLock { state in
                    guard case .settled(let result) = state else {
                        state = .pending(continuation)
                        return nil
                    }
                    return result
                }
                if let settled { continuation.resume(with: settled) }
            }
        }
    }
}

extension TestClock {
    /// Returns once `count` sleepers have registered after `mark`, as ``waitForSleepers(_:after:)`` does, or throws
    /// ``WaitTimeout`` once ``TaskProviderSpy/failureBound`` has passed first. Take `mark` just before the step that
    /// puts the sleepers to sleep: the advance that follows then fires them, never an earlier sleeper alone.
    func expectSleepers(
        _ count: Int = 1, after mark: RegistrationMark, sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        let awaited = count == 1 ? "A sleeper registered after the mark" : "\(count) sleepers registered after the mark"
        try await withFailureBound(awaiting: awaited, sourceLocation: sourceLocation) { [self] in
            try await waitForSleepers(count, after: mark)
        }
    }
}

extension TaskGate {
    /// Returns once the gate opens, as ``wait()`` does, or throws ``WaitTimeout`` once ``TaskProviderSpy/failureBound``
    /// has passed first.
    func expectOpen(sourceLocation: SourceLocation = #_sourceLocation) async throws {
        try await withFailureBound(awaiting: "The gate's opening", sourceLocation: sourceLocation) { [self] in
            try await wait()
        }
    }
}

extension Task where Failure == Never {
    /// The task's value, or ``WaitTimeout`` once ``TaskProviderSpy/failureBound`` has passed first: awaiting ``value``
    /// alone cannot be cancelled, so a task that never finishes would hang the run.
    func expectValue(sourceLocation: SourceLocation = #_sourceLocation) async throws -> Success {
        try await withFailureBound(awaiting: "The task's value", sourceLocation: sourceLocation) { [self] in
            await value
        }
    }
}

extension AsyncProbe {
    /// The next element, as ``next()`` returns it, or ``WaitTimeout`` once ``TaskProviderSpy/failureBound`` has passed
    /// without one: a signal that never comes fails the test instead of hanging the run.
    func expectNext(sourceLocation: SourceLocation = #_sourceLocation) async throws -> Element? {
        let awaited = "An element of AsyncProbe<\(Element.self)>"
        return try await withFailureBound(awaiting: awaited, sourceLocation: sourceLocation) { [self] in
            try await next()
        }
    }
}

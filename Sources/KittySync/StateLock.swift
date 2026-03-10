import Synchronization

public final class StateLock<State: Sendable>: Sendable {
    private let mutex: Mutex<State>

    public init(initialState: sending State) {
        mutex = Mutex(initialState)
    }

    public func withLock<R: Sendable>(_ body: @Sendable (inout State) throws -> R) rethrows -> R {
        try mutex.withLock { state in
            try body(&state)
        }
    }
}

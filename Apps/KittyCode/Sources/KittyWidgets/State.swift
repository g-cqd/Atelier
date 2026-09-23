import Synchronization

/// View-local mutable state, a plain value holder: the event loop re-renders the whole tree after each event.
@propertyWrapper
public struct State<Value: Sendable>: Sendable {
    private let storage: Storage

    public init(wrappedValue: Value) {
        self.storage = Storage(value: wrappedValue)
    }

    public var wrappedValue: Value {
        get { storage.read() }
        nonmutating set { storage.write(newValue) }
    }

    public var projectedValue: Binding<Value> {
        let storage = self.storage
        return Binding(
            get: { storage.read() },
            set: { storage.write($0) }
        )
    }

    private final class Storage: Sendable {
        private let mutex: Mutex<Value>

        init(value: Value) {
            self.mutex = Mutex(value)
        }

        func read() -> Value {
            mutex.withLock { $0 }
        }

        func write(_ newValue: Value) {
            mutex.withLock { $0 = newValue }
        }
    }
}

/// Two-way binding for parent-child state sharing.
@propertyWrapper
public struct Binding<Value: Sendable>: Sendable {
    private let _get: @Sendable () -> Value
    private let _set: @Sendable (Value) -> Void

    public init(get: @escaping @Sendable () -> Value, set: @escaping @Sendable (Value) -> Void) {
        self._get = get
        self._set = set
    }

    public var wrappedValue: Value {
        get { _get() }
        nonmutating set { _set(newValue) }
    }
}

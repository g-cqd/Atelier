/// Property wrapper for view-local mutable state.
///
/// In a terminal UI, re-render is triggered by the event loop after each event,
/// so `@State` is a simple value holder. The runtime re-renders the full view tree
/// each frame (cheap for terminal UIs).
@propertyWrapper
public struct State<Value: Sendable>: Sendable {
    private var storage: Value

    public init(wrappedValue: Value) {
        self.storage = wrappedValue
    }

    public var wrappedValue: Value {
        get { storage }
        nonmutating set {
            // In a full reactive system this would trigger invalidation.
            // For now, the event loop handles re-rendering after each event.
            nonisolated(unsafe) var mutableSelf = self
            mutableSelf.storage = newValue
        }
    }

    public var projectedValue: Binding<Value> {
        Binding(
            get: { self.wrappedValue },
            set: { self.wrappedValue = $0 }
        )
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

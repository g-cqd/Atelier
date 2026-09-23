/// The base of view models: a state change calls `invalidate()`, directly or through `@Published`, so the next frame
/// picks up the new values; `bind(to:)` wires it to the render loop.
///
/// ```swift
/// final class CounterModel: ViewModel {
///     @Published var count: Int = 0
/// }
/// ```
@MainActor
open class ViewModel {
    /// Called on every state change; a no-op until wired to the render loop, as `bind(to:)` does.
    public var invalidate: @MainActor () -> Void = {}

    public init() {}

    /// Calls `invalidate()`.
    public final func notifyChange() {
        invalidate()
    }

    /// Routes future `invalidate()` calls through `refreshSource`. Captures
    /// the source weakly so models don't extend its lifetime.
    public final func bind(to refreshSource: RenderRefreshSource) {
        self.invalidate = { [weak refreshSource] in
            refreshSource?.invalidate()
        }
    }
}

/// Calls the enclosing view model's `invalidate()` on every assignment, never on a read. Valid only on a stored
/// property of a `ViewModel` subclass.
@MainActor
@propertyWrapper
public struct Published<Value> {
    private var storage: Value

    public init(wrappedValue: Value) {
        self.storage = wrappedValue
    }

    /// Unavailable: a `ViewModel` reaches the value through the enclosing-instance subscript.
    @available(
        *, unavailable,
        message: "@Published only works on ViewModel subclasses; use the enclosing-instance access."
    )
    public var wrappedValue: Value {
        get { fatalError("@Published.wrappedValue must be accessed through a ViewModel") }
        set { fatalError("@Published.wrappedValue must be accessed through a ViewModel") }
    }

    public static subscript<EnclosingSelf: ViewModel>(
        _enclosingInstance instance: EnclosingSelf,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<EnclosingSelf, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<EnclosingSelf, Published<Value>>
    ) -> Value {
        get { instance[keyPath: storageKeyPath].storage }
        set {
            instance[keyPath: storageKeyPath].storage = newValue
            instance.invalidate()
        }
    }
}

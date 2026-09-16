/// View-model primitive for the terminal UI framework.
///
/// The renderer re-runs the whole view tree each frame, driven by events
/// coming through the input stream (including the synthetic `.refresh`
/// event injected by `RenderRefreshSource`). View models inherit from
/// `ViewModel` and call `invalidate()` (directly or via `@Published`) when
/// their state changes so the next frame picks up the new values.
///
/// Wiring at the app boundary looks like:
///
/// ```swift
/// let refreshSource = RenderRefreshSource()
/// let model = MyModel()
/// model.invalidate = { [weak refreshSource] in refreshSource?.invalidate() }
/// ```
///
/// Using `@Published` on stored properties of a `ViewModel` subclass causes
/// writes to call `invalidate()` automatically:
///
/// ```swift
/// final class CounterModel: ViewModel {
///     @Published var count: Int = 0
/// }
/// ```
@MainActor
open class ViewModel {
    /// Invoked from `invalidate()`. Wire this to the render refresh source so
    /// state changes show up on the next frame. Default is a no-op so tests
    /// and headless usage stay safe.
    public var invalidate: @MainActor () -> Void = {}

    public init() {}

    /// Convenience for subclasses that prefer call-site readability over
    /// invoking the `invalidate` closure directly.
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

/// Property wrapper that calls `ViewModel.invalidate()` whenever the wrapped
/// value is assigned. Use only on stored properties of a `ViewModel`
/// subclass — Swift's static-subscript dispatch supplies the enclosing
/// instance automatically. Reads do **not** trigger invalidation.
@MainActor
@propertyWrapper
public struct Published<Value> {
    private var storage: Value

    public init(wrappedValue: Value) {
        self.storage = wrappedValue
    }

    /// Required by `@propertyWrapper`. Direct access only succeeds when the
    /// wrapper is attached to a `ViewModel` subclass; the static subscript
    /// below is what the compiler actually calls in that case.
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

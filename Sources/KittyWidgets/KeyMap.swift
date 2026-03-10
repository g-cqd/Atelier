import KittyCodecs
import KittyInput

extension KeyEvent {
    public typealias Modifiers = KeyModifiers
}

/// A composable keybinding map that routes key events to handlers.
public struct KeyMap: Sendable {
    public typealias Handler = @Sendable (KeyEvent) -> EventResult

    private struct Binding: Sendable {
        let matcher: @Sendable (KeyEvent) -> Bool
        let handler: Handler
    }

    private var bindings: [Binding]

    public init() {
        self.bindings = []
    }

    /// Add a binding for a specific key code with optional modifiers.
    public mutating func bind(
        keyCode: UInt32,
        modifiers: KeyEvent.Modifiers = [],
        handler: @escaping Handler
    ) {
        let expectedKeyCode = keyCode
        let expectedModifiers = modifiers

        bindings.append(
            Binding(
                matcher: { event in
                    event.keyCode == expectedKeyCode && event.modifiers == expectedModifiers
                },
                handler: handler
            )
        )
    }

    /// Add a catch-all binding that receives any unhandled key.
    public mutating func bindDefault(handler: @escaping Handler) {
        bindings.append(
            Binding(
                matcher: { _ in true },
                handler: handler
            )
        )
    }

    /// Process a key event through the binding chain.
    /// Returns .handled if a binding matched, .ignored otherwise.
    public func handle(_ event: KeyEvent) -> EventResult {
        for binding in bindings {
            if binding.matcher(event), binding.handler(event) == .handled {
                return .handled
            }
        }

        return .ignored
    }

    /// Merge another keymap (other's bindings take priority).
    public func merging(_ other: KeyMap) -> KeyMap {
        var combined = KeyMap()
        combined.bindings = other.bindings + bindings
        return combined
    }
}

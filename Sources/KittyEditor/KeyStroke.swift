import KittyCodecs

public struct KeyStroke: Hashable, Sendable {
    public var keyCode: UInt32
    public var modifiers: KeyModifiers

    public init(from key: KeyEvent) {
        self.keyCode = key.keyCode
        self.modifiers = key.modifiers.subtracting([.capsLock, .numLock])
    }

    public init(keyCode: UInt32, modifiers: KeyModifiers = []) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

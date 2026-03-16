import KittyCodecs

struct KeyStroke: Hashable, Sendable {
    var keyCode: UInt32
    var modifiers: KeyModifiers

    init(from key: KeyEvent) {
        self.keyCode = key.keyCode
        self.modifiers = key.modifiers.subtracting([.capsLock, .numLock])
    }

    init(keyCode: UInt32, modifiers: KeyModifiers = []) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
}

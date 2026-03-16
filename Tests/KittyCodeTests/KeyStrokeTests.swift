import KittyCodecs
import KittyInput
import Testing

@testable import KittyCode

@Suite
struct KeyStrokeTests {

    @Test
    func capsLockStrippedDuringNormalization() {
        let key = KeyEvent(keyCode: AsciiKey.c, modifiers: [.ctrl, .capsLock])
        let stroke = KeyStroke(from: key)
        #expect(stroke.modifiers == .ctrl)
    }

    @Test
    func numLockStrippedDuringNormalization() {
        let key = KeyEvent(keyCode: AsciiKey.z, modifiers: [.super, .numLock])
        let stroke = KeyStroke(from: key)
        #expect(stroke.modifiers == .super)
    }

    @Test
    func bothLockModifiersStripped() {
        let key = KeyEvent(keyCode: AsciiKey.v, modifiers: [.meta, .capsLock, .numLock])
        let stroke = KeyStroke(from: key)
        #expect(stroke.modifiers == .meta)
    }

    @Test
    func equalityIgnoresLockModifiers() {
        let a = KeyStroke(from: KeyEvent(keyCode: AsciiKey.o, modifiers: [.ctrl, .capsLock]))
        let b = KeyStroke(from: KeyEvent(keyCode: AsciiKey.o, modifiers: .ctrl))
        #expect(a == b)
    }

    @Test
    func hashConsistencyWithLockModifiers() {
        let a = KeyStroke(from: KeyEvent(keyCode: AsciiKey.n, modifiers: [.ctrl, .numLock]))
        let b = KeyStroke(from: KeyEvent(keyCode: AsciiKey.n, modifiers: .ctrl))
        #expect(a.hashValue == b.hashValue)
    }

    @Test
    func directInitPreservesValues() {
        let stroke = KeyStroke(keyCode: 42, modifiers: [.shift, .alt])
        #expect(stroke.keyCode == 42)
        #expect(stroke.modifiers == [.shift, .alt])
    }
}

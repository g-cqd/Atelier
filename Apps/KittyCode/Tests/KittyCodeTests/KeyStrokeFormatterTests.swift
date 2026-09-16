import KittyCodecs
import KittyInput
import Testing

@testable import KittyEditor

@Suite
struct KeyStrokeFormatterTests {

    @Test
    func ctrlO() {
        let stroke = KeyStroke(keyCode: AsciiKey.o, modifiers: .ctrl)
        #expect(KeyStrokeFormatter.label(for: stroke) == "Ctrl+O")
    }

    @Test
    func cmdShiftZ() {
        let stroke = KeyStroke(keyCode: AsciiKey.z, modifiers: [.super, .shift])
        #expect(KeyStrokeFormatter.label(for: stroke) == "Shift+Cmd+Z")
    }

    @Test
    func escape() {
        let stroke = KeyStroke(keyCode: AsciiKey.escape, modifiers: [])
        #expect(KeyStrokeFormatter.label(for: stroke) == "Esc")
    }

    @Test
    func plainEnter() {
        let stroke = KeyStroke(keyCode: Key.enter.rawValue, modifiers: [])
        #expect(KeyStrokeFormatter.label(for: stroke) == "Enter")
    }

    @Test
    func altB() {
        let stroke = KeyStroke(keyCode: AsciiKey.b, modifiers: .alt)
        #expect(KeyStrokeFormatter.label(for: stroke) == "Alt+B")
    }

    @Test
    func cmdC() {
        let stroke = KeyStroke(keyCode: AsciiKey.c, modifiers: .super)
        #expect(KeyStrokeFormatter.label(for: stroke) == "Cmd+C")
    }

    @Test
    func ctrlPageDown() {
        let stroke = KeyStroke(keyCode: Key.pageDown.rawValue, modifiers: .ctrl)
        #expect(KeyStrokeFormatter.label(for: stroke) == "Ctrl+PageDown")
    }
}

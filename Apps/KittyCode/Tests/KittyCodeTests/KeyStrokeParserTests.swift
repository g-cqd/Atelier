import KittyCodecs
import KittyInput
import Testing

@testable import KittyEditor

@Suite
struct KeyStrokeParserTests {
    @Test
    func ctrlPageDown() {
        let result = KeyStrokeParser.parse("ctrl+pagedown")
        #expect(result == KeyStroke(keyCode: Key.pageDown.rawValue, modifiers: .ctrl))
    }

    @Test
    func cmdShiftZ() {
        let result = KeyStrokeParser.parse("cmd+shift+z")
        #expect(result == KeyStroke(keyCode: AsciiKey.z, modifiers: [.super, .shift]))
    }

    @Test
    func altB() {
        let result = KeyStrokeParser.parse("alt+b")
        #expect(result == KeyStroke(keyCode: AsciiKey.b, modifiers: .alt))
    }

    @Test
    func ctrlQ() {
        let result = KeyStrokeParser.parse("ctrl+q")
        #expect(result == KeyStroke(keyCode: AsciiKey.q, modifiers: .ctrl))
    }

    @Test
    func singleKeyEnter() {
        let result = KeyStrokeParser.parse("enter")
        #expect(result == KeyStroke(keyCode: Key.enter.rawValue, modifiers: []))
    }

    @Test
    func emptyStringReturnsNil() {
        #expect(KeyStrokeParser.parse("") == nil)
    }

    @Test
    func invalidStringReturnsNil() {
        #expect(KeyStrokeParser.parse("foo+bar") == nil)
    }

    @Test
    func caseInsensitive() {
        let lower = KeyStrokeParser.parse("ctrl+pagedown")
        let upper = KeyStrokeParser.parse("Ctrl+PageDown")
        #expect(lower == upper)
    }

    @Test
    func commandSynonyms() {
        let cmd = KeyStrokeParser.parse("cmd+s")
        let command = KeyStrokeParser.parse("command+s")
        let superKey = KeyStrokeParser.parse("super+s")
        #expect(cmd == command)
        #expect(cmd == superKey)
    }

    @Test
    func altOptionSynonyms() {
        let alt = KeyStrokeParser.parse("alt+b")
        let option = KeyStrokeParser.parse("option+b")
        #expect(alt == option)
    }

    @Test
    func escapeKey() {
        let result = KeyStrokeParser.parse("esc")
        #expect(result == KeyStroke(keyCode: AsciiKey.escape, modifiers: []))
        let result2 = KeyStrokeParser.parse("escape")
        #expect(result2 == result)
    }

    @Test
    func arrowKeys() {
        #expect(KeyStrokeParser.parse("up") == KeyStroke(keyCode: Key.up.rawValue, modifiers: []))
        #expect(
            KeyStrokeParser.parse("down") == KeyStroke(keyCode: Key.down.rawValue, modifiers: []))
        #expect(
            KeyStrokeParser.parse("left") == KeyStroke(keyCode: Key.left.rawValue, modifiers: []))
        #expect(
            KeyStrokeParser.parse("right") == KeyStroke(keyCode: Key.right.rawValue, modifiers: []))
    }
}

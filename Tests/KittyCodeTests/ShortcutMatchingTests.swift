import Foundation
import KittyCodecs
import KittyFileTree
import KittyGit
import KittyRenderer
import KittySyntax
import KittyTerminal
import KittyText
import KittyWidgets
import KittyWorkspace
import Testing

@testable import KittyCode

@Suite
@MainActor
struct ShortcutMatchingTests {
    private func makeConfig(
        clipboard: KittyConfig.KeybindingsConfig.ShortcutModifier = .command,
        history: KittyConfig.KeybindingsConfig.ShortcutModifier = .command
    ) -> KittyConfig {
        var config = KittyConfig()
        config.keybindings.clipboardModifier = clipboard
        config.keybindings.historyModifier = history
        return config
    }

    @Test
    func `isConfiguredCopyShortcut with clipboardModifier both matches super`() {
        let config = makeConfig(clipboard: .both)
        let key = KeyEvent(keyCode: AsciiKey.c, modifiers: .super)
        #expect(isConfiguredCopyShortcut(key, config: config))
    }

    @Test
    func `isConfiguredCopyShortcut with clipboardModifier both matches ctrl`() {
        let config = makeConfig(clipboard: .both)
        let key = KeyEvent(keyCode: AsciiKey.c, modifiers: .ctrl)
        #expect(isConfiguredCopyShortcut(key, config: config))
    }

    @Test
    func `isConfiguredCopyShortcut with clipboardModifier both rejects no modifier`() {
        let config = makeConfig(clipboard: .both)
        let key = KeyEvent(keyCode: AsciiKey.c, modifiers: [])
        #expect(!isConfiguredCopyShortcut(key, config: config))
    }

    @Test
    func `isConfiguredCopyShortcut capsLock plus Cmd C still matches`() {
        let config = makeConfig(clipboard: .command)
        let key = KeyEvent(keyCode: AsciiKey.c, modifiers: [.super, .capsLock])
        #expect(isConfiguredCopyShortcut(key, config: config))
    }

    @Test
    func `isConfiguredCopyShortcut Shift Cmd C does not match copy`() {
        let config = makeConfig(clipboard: .command)
        let key = KeyEvent(keyCode: AsciiKey.c, modifiers: [.super, .shift])
        #expect(!isConfiguredCopyShortcut(key, config: config))
    }

    @Test
    func `isConfiguredCutShortcut matches super X`() {
        let config = makeConfig(clipboard: .command)
        let key = KeyEvent(keyCode: AsciiKey.x, modifiers: .super)
        #expect(isConfiguredCutShortcut(key, config: config))
    }

    @Test
    func `isConfiguredPasteShortcut matches super V`() {
        let config = makeConfig(clipboard: .command)
        let key = KeyEvent(keyCode: AsciiKey.v, modifiers: .super)
        #expect(isConfiguredPasteShortcut(key, config: config))
    }

    @Test
    func `isConfiguredRedoShortcut matches Cmd Y`() {
        let config = makeConfig(history: .command)
        let key = KeyEvent(keyCode: AsciiKey.y, modifiers: .super)
        #expect(isConfiguredRedoShortcut(key, config: config))
    }

    @Test
    func `isConfiguredRedoShortcut matches Cmd Shift Z`() {
        let config = makeConfig(history: .command)
        let key = KeyEvent(keyCode: AsciiKey.z, modifiers: [.super, .shift])
        #expect(isConfiguredRedoShortcut(key, config: config))
    }

    @Test
    func `isConfiguredRedoShortcut does not match plain Cmd Z`() {
        let config = makeConfig(history: .command)
        let key = KeyEvent(keyCode: AsciiKey.z, modifiers: .super)
        #expect(!isConfiguredRedoShortcut(key, config: config))
    }

    @Test
    func `isConfiguredUndoShortcut with historyModifier control matches Ctrl Z`() {
        let config = makeConfig(history: .control)
        let key = KeyEvent(keyCode: AsciiKey.z, modifiers: .ctrl)
        #expect(isConfiguredUndoShortcut(key, config: config))
    }

    @Test
    func `isConfiguredUndoShortcut with historyModifier control rejects super Z`() {
        let config = makeConfig(history: .control)
        let key = KeyEvent(keyCode: AsciiKey.z, modifiers: .super)
        #expect(!isConfiguredUndoShortcut(key, config: config))
    }

    @Test
    func `isConfiguredCopyShortcut uppercase C key code matches lowercase c shortcut`() {
        // 0x43 = 'C', 0x63 = 'c'; matchesShortcutKey uses letter - 32 to support uppercase
        let config = makeConfig(clipboard: .command)
        let uppercaseC: UInt32 = 0x43
        let key = KeyEvent(keyCode: uppercaseC, modifiers: .super)
        #expect(isConfiguredCopyShortcut(key, config: config))
    }

    @Test
    func `isConfiguredRedoShortcut with historyModifier both matches Ctrl Y`() {
        let config = makeConfig(history: .both)
        let key = KeyEvent(keyCode: AsciiKey.y, modifiers: .ctrl)
        #expect(isConfiguredRedoShortcut(key, config: config))
    }
}

import KittyCodecs
import KittyInput
import Testing

@testable import KittyCode

@Suite
struct KeymapResolverTests {

    private func stroke(_ keyCode: UInt32, _ modifiers: KeyModifiers = []) -> KeyStroke {
        KeyStroke(keyCode: keyCode, modifiers: modifiers)
    }

    // MARK: - Global hotkeys

    @Test
    func ctrlOSaveFile() {
        let resolver = KeymapResolver(config: KittyConfig())
        #expect(resolver.resolve(stroke(AsciiKey.o, .ctrl), context: .editor) == .saveFile)
        #expect(resolver.resolve(stroke(AsciiKey.o, .ctrl), context: .tree) == .saveFile)
    }

    @Test
    func ctrlNNewFile() {
        let resolver = KeymapResolver(config: KittyConfig())
        #expect(resolver.resolve(stroke(AsciiKey.n, .ctrl), context: .editor) == .newFile)
    }

    @Test
    func ctrlBToggleSidebar() {
        let resolver = KeymapResolver(config: KittyConfig())
        #expect(resolver.resolve(stroke(AsciiKey.b, .ctrl), context: .editor) == .toggleSidebar)
    }

    @Test
    func ctrlHCycleFileVisibility() {
        let resolver = KeymapResolver(config: KittyConfig())
        #expect(
            resolver.resolve(stroke(AsciiKey.h, .ctrl), context: .tree) == .cycleFileVisibility)
    }

    // MARK: - Tab navigation

    @Test
    func ctrlPageDownNextTab() {
        let resolver = KeymapResolver(config: KittyConfig())
        #expect(resolver.resolve(stroke(Key.pageDown.rawValue, .ctrl), context: .editor) == .nextTab)
    }

    @Test
    func ctrlPageUpPreviousTab() {
        let resolver = KeymapResolver(config: KittyConfig())
        #expect(
            resolver.resolve(stroke(Key.pageUp.rawValue, .ctrl), context: .editor) == .previousTab)
    }

    // MARK: - Close tab (nano vs vim)

    @Test
    func ctrlWCloseTabInNanoMode() {
        var config = KittyConfig()
        config.keybindingMode = .nano
        let resolver = KeymapResolver(config: config)
        #expect(resolver.resolve(stroke(AsciiKey.w, .ctrl), context: .editor) == .closeTab)
    }

    @Test
    func ctrlWNotBoundInVimMode() {
        var config = KittyConfig()
        config.keybindingMode = .vim
        let resolver = KeymapResolver(config: config)
        #expect(resolver.resolve(stroke(AsciiKey.w, .ctrl), context: .editor) == nil)
    }

    // MARK: - Clipboard (default: command modifier)

    @Test
    func cmdCCopyWithDefaultModifier() {
        let resolver = KeymapResolver(config: KittyConfig())
        #expect(resolver.resolve(stroke(AsciiKey.c, .super), context: .editor) == .copy)
    }

    @Test
    func metaCCopyWithDefaultModifier() {
        let resolver = KeymapResolver(config: KittyConfig())
        #expect(resolver.resolve(stroke(AsciiKey.c, .meta), context: .editor) == .copy)
    }

    @Test
    func ctrlCCopyWhenControlModifier() {
        var config = KittyConfig()
        config.keybindings.clipboardModifier = .control
        let resolver = KeymapResolver(config: config)
        #expect(resolver.resolve(stroke(AsciiKey.c, .ctrl), context: .editor) == .copy)
    }

    @Test
    func cmdVPasteWithDefaultModifier() {
        let resolver = KeymapResolver(config: KittyConfig())
        #expect(resolver.resolve(stroke(AsciiKey.v, .super), context: .editor) == .paste)
    }

    // MARK: - Cut with non-control modifier

    @Test
    func cmdXCutWithDefaultModifier() {
        let resolver = KeymapResolver(config: KittyConfig())
        #expect(resolver.resolve(stroke(AsciiKey.x, .super), context: .editor) == .cut)
    }

    // MARK: - Ctrl+X always maps to handleCtrlX

    @Test
    func ctrlXMapsToHandleCtrlX() {
        let resolver = KeymapResolver(config: KittyConfig())
        #expect(resolver.resolve(stroke(AsciiKey.x, .ctrl), context: .editor) == .handleCtrlX)
    }

    @Test
    func ctrlXHandleCtrlXEvenWithControlClipboardModifier() {
        var config = KittyConfig()
        config.keybindings.clipboardModifier = .control
        let resolver = KeymapResolver(config: config)
        #expect(resolver.resolve(stroke(AsciiKey.x, .ctrl), context: .editor) == .handleCtrlX)
    }

    // MARK: - History (default: command modifier)

    @Test
    func cmdZUndo() {
        let resolver = KeymapResolver(config: KittyConfig())
        #expect(resolver.resolve(stroke(AsciiKey.z, .super), context: .editor) == .undo)
    }

    @Test
    func cmdYRedo() {
        let resolver = KeymapResolver(config: KittyConfig())
        #expect(resolver.resolve(stroke(AsciiKey.y, .super), context: .editor) == .redo)
    }

    @Test
    func cmdShiftZRedo() {
        let resolver = KeymapResolver(config: KittyConfig())
        #expect(
            resolver.resolve(stroke(AsciiKey.z, [.super, .shift]), context: .editor) == .redo)
    }

    @Test
    func ctrlZUndoWhenControlModifier() {
        var config = KittyConfig()
        config.keybindings.historyModifier = .control
        let resolver = KeymapResolver(config: config)
        #expect(resolver.resolve(stroke(AsciiKey.z, .ctrl), context: .editor) == .undo)
    }

    // MARK: - Unbound

    @Test
    func unboundKeystrokeReturnsNil() {
        let resolver = KeymapResolver(config: KittyConfig())
        #expect(resolver.resolve(stroke(AsciiKey.q, .ctrl), context: .editor) == nil)
    }
}

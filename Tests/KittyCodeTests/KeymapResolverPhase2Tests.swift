import KittyCodecs
import KittyInput
import Testing

@testable import KittyCode

@Suite
struct KeymapResolverPhase2Tests {

    private func stroke(_ keyCode: UInt32, _ modifiers: KeyModifiers = []) -> KeyStroke {
        KeyStroke(keyCode: keyCode, modifiers: modifiers)
    }

    // MARK: - Escape and force quit

    @Test
    func escapeResolvesGlobally() {
        let resolver = KeymapResolver(config: KittyConfig())
        #expect(resolver.resolve(stroke(AsciiKey.escape), context: .editor) == .escapeEditor)
        #expect(resolver.resolve(stroke(AsciiKey.escape), context: .tree) == .escapeEditor)
        #expect(
            resolver.resolve(stroke(AsciiKey.escape), context: .editorVimNormal) == .escapeEditor)
    }

    @Test
    func forceQuitResolvesGlobally() {
        let resolver = KeymapResolver(config: KittyConfig())
        #expect(resolver.resolve(stroke(3), context: .editor) == .forceQuit)
        #expect(resolver.resolve(stroke(3), context: .tree) == .forceQuit)
    }

    @Test
    func escapeDoesNotResolveOnRepeat() {
        let resolver = KeymapResolver(config: KittyConfig())
        #expect(
            resolver.resolve(stroke(AsciiKey.escape), context: .tree, isRepeat: true) == nil)
    }

    // MARK: - Editor context bindings

    @Test
    func altBWordBackwardInEditor() {
        let resolver = KeymapResolver(config: KittyConfig())
        #expect(
            resolver.resolve(stroke(AsciiKey.b, .alt), context: .editor) == .editorWordBackward)
    }

    @Test
    func altFWordForwardInEditor() {
        let resolver = KeymapResolver(config: KittyConfig())
        #expect(
            resolver.resolve(stroke(AsciiKey.f, .alt), context: .editor) == .editorWordForward)
    }

    @Test
    func altBDoesNotResolveInTree() {
        let resolver = KeymapResolver(config: KittyConfig())
        #expect(resolver.resolve(stroke(AsciiKey.b, .alt), context: .tree) == nil)
    }

    @Test
    func editorWordNavResolvesOnRepeat() {
        let resolver = KeymapResolver(config: KittyConfig())
        #expect(
            resolver.resolve(stroke(AsciiKey.b, .alt), context: .editor, isRepeat: true)
                == .editorWordBackward)
    }

    // MARK: - Vim normal mode context bindings

    @Test
    func vimNormalModeHJKL() {
        let resolver = KeymapResolver(config: KittyConfig())
        #expect(
            resolver.resolve(stroke(AsciiKey.h), context: .editorVimNormal) == .vimMoveLeft)
        #expect(
            resolver.resolve(stroke(AsciiKey.j), context: .editorVimNormal) == .vimMoveDown)
        #expect(
            resolver.resolve(stroke(AsciiKey.k), context: .editorVimNormal) == .vimMoveUp)
        #expect(
            resolver.resolve(stroke(AsciiKey.l), context: .editorVimNormal) == .vimMoveRight)
    }

    @Test
    func vimEnterInsert() {
        let resolver = KeymapResolver(config: KittyConfig())
        #expect(
            resolver.resolve(stroke(AsciiKey.i), context: .editorVimNormal) == .vimEnterInsert)
    }

    @Test
    func vimGotoLastLine() {
        let resolver = KeymapResolver(config: KittyConfig())
        #expect(
            resolver.resolve(stroke(AsciiKey.g, .shift), context: .editorVimNormal)
                == .vimGotoLastLine)
    }

    @Test
    func vimBindingsDoNotLeakToEditorContext() {
        let resolver = KeymapResolver(config: KittyConfig())
        #expect(resolver.resolve(stroke(AsciiKey.j), context: .editor) == nil)
        #expect(resolver.resolve(stroke(AsciiKey.h), context: .editor) == nil)
        #expect(resolver.resolve(stroke(AsciiKey.i), context: .editor) == nil)
    }

    @Test
    func vimBindingsDoNotLeakToTreeContext() {
        let resolver = KeymapResolver(config: KittyConfig())
        #expect(resolver.resolve(stroke(AsciiKey.j), context: .tree) == nil)
    }

    // MARK: - Tree context bindings

    @Test
    func treeNavigation() {
        let resolver = KeymapResolver(config: KittyConfig())
        #expect(
            resolver.resolve(stroke(Key.down.rawValue), context: .tree) == .treeDown)
        #expect(
            resolver.resolve(stroke(Key.up.rawValue), context: .tree) == .treeUp)
        #expect(
            resolver.resolve(stroke(Key.enter.rawValue), context: .tree) == .treeSelect)
        #expect(
            resolver.resolve(stroke(Key.enterAlt.rawValue), context: .tree) == .treeSelect)
        #expect(
            resolver.resolve(stroke(Key.right.rawValue), context: .tree) == .treeExpandOrOpen)
        #expect(
            resolver.resolve(stroke(Key.left.rawValue), context: .tree) == .treeCollapse)
    }

    @Test
    func treeBindingsDoNotLeakToEditorContext() {
        let resolver = KeymapResolver(config: KittyConfig())
        // Down arrow in editor should resolve to editorMoveDown, not treeDown
        #expect(resolver.resolve(stroke(Key.down.rawValue), context: .editor) != .treeDown)
        #expect(resolver.resolve(stroke(Key.down.rawValue), context: .editor) == .editorMoveDown)
    }

    @Test
    func treeNavResolvesOnRepeat() {
        let resolver = KeymapResolver(config: KittyConfig())
        #expect(
            resolver.resolve(stroke(Key.down.rawValue), context: .tree, isRepeat: true)
                == .treeDown)
    }

    // MARK: - Context priority over global

    @Test
    func contextBindingTakesPriorityOverGlobal() {
        // Ctrl+B is globally toggleSidebar, but if a context binding existed for it,
        // context would win. Test the priority mechanism with existing bindings.
        let resolver = KeymapResolver(config: KittyConfig())
        // In tree context, Down arrow resolves to treeDown (context), not any global
        let result = resolver.resolve(stroke(Key.down.rawValue), context: .tree)
        #expect(result == .treeDown)
    }
}

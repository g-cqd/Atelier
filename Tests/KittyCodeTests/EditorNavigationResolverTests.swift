import KittyCodecs
import KittyInput
import Testing

@testable import KittyCode

@Suite
struct EditorNavigationResolverTests {

    private func stroke(_ keyCode: UInt32, _ modifiers: KeyModifiers = []) -> KeyStroke {
        KeyStroke(keyCode: keyCode, modifiers: modifiers)
    }

    // MARK: - Arrow keys

    @Test
    func arrowKeysResolveInEditorContext() {
        let resolver = KeymapResolver(config: KittyConfig())
        #expect(resolver.resolve(stroke(Key.down.rawValue), context: .editor) == .editorMoveDown)
        #expect(resolver.resolve(stroke(Key.up.rawValue), context: .editor) == .editorMoveUp)
        #expect(resolver.resolve(stroke(Key.left.rawValue), context: .editor) == .editorMoveLeft)
        #expect(resolver.resolve(stroke(Key.right.rawValue), context: .editor) == .editorMoveRight)
    }

    @Test
    func arrowKeysResolveOnRepeat() {
        let resolver = KeymapResolver(config: KittyConfig())
        #expect(
            resolver.resolve(stroke(Key.down.rawValue), context: .editor, isRepeat: true)
                == .editorMoveDown)
    }

    @Test
    func arrowKeysDoNotResolveInTreeContext() {
        let resolver = KeymapResolver(config: KittyConfig())
        // Tree context has its own bindings for arrow keys
        #expect(resolver.resolve(stroke(Key.down.rawValue), context: .tree) == .treeDown)
        #expect(resolver.resolve(stroke(Key.up.rawValue), context: .tree) == .treeUp)
    }

    // MARK: - Page navigation

    @Test
    func altArrowsResolveToPageNavigation() {
        let resolver = KeymapResolver(config: KittyConfig())
        #expect(
            resolver.resolve(stroke(Key.down.rawValue, .alt), context: .editor)
                == .editorMoveDownPage)
        #expect(
            resolver.resolve(stroke(Key.up.rawValue, .alt), context: .editor)
                == .editorMoveUpPage)
    }

    @Test
    func pageUpDownResolveInEditorContext() {
        let resolver = KeymapResolver(config: KittyConfig())
        #expect(
            resolver.resolve(stroke(Key.pageDown.rawValue), context: .editor)
                == .editorMoveDownPage)
        #expect(
            resolver.resolve(stroke(Key.pageUp.rawValue), context: .editor)
                == .editorMoveUpPage)
    }

    // MARK: - Word navigation aliases

    @Test
    func ctrlLeftRightResolveToWordNavigation() {
        let resolver = KeymapResolver(config: KittyConfig())
        #expect(
            resolver.resolve(stroke(Key.left.rawValue, .ctrl), context: .editor)
                == .editorWordBackward)
        #expect(
            resolver.resolve(stroke(Key.right.rawValue, .ctrl), context: .editor)
                == .editorWordForward)
    }

    // MARK: - Home/End

    @Test
    func homeEndResolveInEditorContext() {
        let resolver = KeymapResolver(config: KittyConfig())
        #expect(resolver.resolve(stroke(Key.home.rawValue), context: .editor) == .editorHome)
        #expect(resolver.resolve(stroke(Key.end.rawValue), context: .editor) == .editorEnd)
    }

    // MARK: - Enter and Backspace

    @Test
    func enterResolvesInEditorContext() {
        let resolver = KeymapResolver(config: KittyConfig())
        #expect(
            resolver.resolve(stroke(Key.enter.rawValue), context: .editor)
                == .editorInsertNewline)
        #expect(
            resolver.resolve(stroke(Key.enterAlt.rawValue), context: .editor)
                == .editorInsertNewline)
    }

    @Test
    func backspaceResolvesInEditorContext() {
        let resolver = KeymapResolver(config: KittyConfig())
        #expect(
            resolver.resolve(stroke(Key.backspace.rawValue), context: .editor)
                == .editorDeleteBackward)
        #expect(
            resolver.resolve(stroke(Key.backspaceAlt.rawValue), context: .editor)
                == .editorDeleteBackward)
    }

    @Test
    func enterInTreeResolvesToTreeSelect() {
        let resolver = KeymapResolver(config: KittyConfig())
        #expect(
            resolver.resolve(stroke(Key.enter.rawValue), context: .tree)
                == .treeSelect)
    }

    // MARK: - isEditorNavigation

    @Test
    func isEditorNavigationTrueForMovementCommands() {
        let navCommands: [CommandID] = [
            .editorMoveDown, .editorMoveUp, .editorMoveLeft, .editorMoveRight,
            .editorMoveDownPage, .editorMoveUpPage, .editorHome, .editorEnd,
            .editorWordForward, .editorWordBackward,
        ]
        for command in navCommands {
            #expect(command.isEditorNavigation, "Expected \(command) to be navigation")
        }
    }

    @Test
    func isEditorNavigationFalseForNonMovementCommands() {
        let nonNavCommands: [CommandID] = [
            .editorInsertNewline, .editorDeleteBackward, .saveFile, .copy,
        ]
        for command in nonNavCommands {
            #expect(!command.isEditorNavigation, "Expected \(command) to not be navigation")
        }
    }
}

import KittyCodecs
import KittyInput

struct KeymapResolver: Sendable {
    enum ResolveResult: Sendable, Equatable {
        case command(CommandID)
        case partial
        case none
    }

    private let globalBindings: [KeyStroke: CommandID]
    private let contextBindings: [KeyContext: [KeyStroke: CommandID]]
    private let sequenceBindings: [KeyContext: [[KeyStroke]: CommandID]]

    init(config: KittyConfig) {
        var global: [KeyStroke: CommandID] = [:]
        var context: [KeyContext: [KeyStroke: CommandID]] = [:]

        switch config.keybindingMode {
        case .nano, .vim:
            Self.buildNanoVimDefaults(config: config, global: &global)
        case .kittycode:
            Self.buildKittyCodeDefaults(config: config, global: &global)
        }

        // Editor context bindings
        var editorBindings: [KeyStroke: CommandID] = [:]
        editorBindings[KeyStroke(keyCode: AsciiKey.b, modifiers: .alt)] = .editorWordBackward
        editorBindings[KeyStroke(keyCode: AsciiKey.f, modifiers: .alt)] = .editorWordForward

        // Arrow keys
        editorBindings[KeyStroke(keyCode: Key.down.rawValue)] = .editorMoveDown
        editorBindings[KeyStroke(keyCode: Key.up.rawValue)] = .editorMoveUp
        editorBindings[KeyStroke(keyCode: Key.left.rawValue)] = .editorMoveLeft
        editorBindings[KeyStroke(keyCode: Key.right.rawValue)] = .editorMoveRight

        // Page navigation
        editorBindings[KeyStroke(keyCode: Key.down.rawValue, modifiers: .alt)] = .editorMoveDownPage
        editorBindings[KeyStroke(keyCode: Key.up.rawValue, modifiers: .alt)] = .editorMoveUpPage
        editorBindings[KeyStroke(keyCode: Key.pageDown.rawValue)] = .editorMoveDownPage
        editorBindings[KeyStroke(keyCode: Key.pageUp.rawValue)] = .editorMoveUpPage

        // Word navigation aliases (Ctrl+Left/Right, Alt+Left/Right)
        editorBindings[KeyStroke(keyCode: Key.left.rawValue, modifiers: .ctrl)] = .editorWordBackward
        editorBindings[KeyStroke(keyCode: Key.right.rawValue, modifiers: .ctrl)] =
            .editorWordForward
        editorBindings[KeyStroke(keyCode: Key.left.rawValue, modifiers: .alt)] = .editorWordBackward
        editorBindings[KeyStroke(keyCode: Key.right.rawValue, modifiers: .alt)] =
            .editorWordForward

        // Home/End
        editorBindings[KeyStroke(keyCode: Key.home.rawValue)] = .editorHome
        editorBindings[KeyStroke(keyCode: Key.end.rawValue)] = .editorEnd

        // Enter and Backspace
        editorBindings[KeyStroke(keyCode: Key.enter.rawValue)] = .editorInsertNewline
        editorBindings[KeyStroke(keyCode: Key.enterAlt.rawValue)] = .editorInsertNewline
        editorBindings[KeyStroke(keyCode: Key.backspace.rawValue)] = .editorDeleteBackward
        editorBindings[KeyStroke(keyCode: Key.backspaceAlt.rawValue)] = .editorDeleteBackward

        context[.editor] = editorBindings

        // Vim normal mode context bindings
        var vimNormalBindings: [KeyStroke: CommandID] = [:]
        vimNormalBindings[KeyStroke(keyCode: AsciiKey.colon)] = .vimEnterCommandLine
        vimNormalBindings[KeyStroke(keyCode: AsciiKey.colon, modifiers: .shift)] =
            .vimEnterCommandLine
        vimNormalBindings[KeyStroke(keyCode: AsciiKey.i)] = .vimEnterInsert
        vimNormalBindings[KeyStroke(keyCode: AsciiKey.h)] = .vimMoveLeft
        vimNormalBindings[KeyStroke(keyCode: AsciiKey.j)] = .vimMoveDown
        vimNormalBindings[KeyStroke(keyCode: AsciiKey.k)] = .vimMoveUp
        vimNormalBindings[KeyStroke(keyCode: AsciiKey.l)] = .vimMoveRight
        vimNormalBindings[KeyStroke(keyCode: AsciiKey.g, modifiers: .shift)] = .vimGotoLastLine
        vimNormalBindings[KeyStroke(keyCode: AsciiKey.v)] = .vimEnterVisual
        vimNormalBindings[KeyStroke(keyCode: AsciiKey.v - 32, modifiers: .shift)] =
            .vimEnterVisualLine
        vimNormalBindings[KeyStroke(keyCode: AsciiKey.w)] = .vimMoveWordForward
        vimNormalBindings[KeyStroke(keyCode: AsciiKey.b)] = .vimMoveWordBackward
        vimNormalBindings[KeyStroke(keyCode: UInt32(Character("0").asciiValue!))] =
            .vimMoveLineStart
        vimNormalBindings[
            KeyStroke(keyCode: UInt32(Character("$").asciiValue!), modifiers: .shift)] =
            .vimMoveLineEnd
        vimNormalBindings[KeyStroke(keyCode: AsciiKey.p)] = .vimPaste
        vimNormalBindings[KeyStroke(keyCode: UInt32(Character("/").asciiValue!))] =
            .vimSearchForward
        context[.editorVimNormal] = vimNormalBindings

        // Vim visual mode context bindings
        var vimVisualBindings: [KeyStroke: CommandID] = [:]
        vimVisualBindings[KeyStroke(keyCode: AsciiKey.escape)] = .vimExitVisual
        vimVisualBindings[KeyStroke(keyCode: AsciiKey.h)] = .vimMoveLeft
        vimVisualBindings[KeyStroke(keyCode: AsciiKey.j)] = .vimMoveDown
        vimVisualBindings[KeyStroke(keyCode: AsciiKey.k)] = .vimMoveUp
        vimVisualBindings[KeyStroke(keyCode: AsciiKey.l)] = .vimMoveRight
        vimVisualBindings[KeyStroke(keyCode: AsciiKey.w)] = .vimMoveWordForward
        vimVisualBindings[KeyStroke(keyCode: AsciiKey.b)] = .vimMoveWordBackward
        vimVisualBindings[KeyStroke(keyCode: UInt32(Character("0").asciiValue!))] =
            .vimMoveLineStart
        vimVisualBindings[
            KeyStroke(keyCode: UInt32(Character("$").asciiValue!), modifiers: .shift)] =
            .vimMoveLineEnd
        context[.editorVimVisual] = vimVisualBindings

        // Tree context bindings
        var treeBindings: [KeyStroke: CommandID] = [:]
        treeBindings[KeyStroke(keyCode: Key.down.rawValue)] = .treeDown
        treeBindings[KeyStroke(keyCode: Key.up.rawValue)] = .treeUp
        treeBindings[KeyStroke(keyCode: Key.enter.rawValue)] = .treeSelect
        treeBindings[KeyStroke(keyCode: Key.enterAlt.rawValue)] = .treeSelect
        treeBindings[KeyStroke(keyCode: Key.right.rawValue)] = .treeExpandOrOpen
        treeBindings[KeyStroke(keyCode: Key.left.rawValue)] = .treeCollapse
        treeBindings[KeyStroke(keyCode: AsciiKey.tab)] = .focusNext
        treeBindings[KeyStroke(keyCode: AsciiKey.tab, modifiers: .shift)] = .focusPrevious
        context[.tree] = treeBindings

        // Search panel context bindings
        var searchPanelBindings: [KeyStroke: CommandID] = [:]
        searchPanelBindings[KeyStroke(keyCode: Key.enter.rawValue)] = .searchNext
        searchPanelBindings[KeyStroke(keyCode: AsciiKey.escape)] = .searchClose
        searchPanelBindings[KeyStroke(keyCode: AsciiKey.tab)] = .searchFocusResults
        context[.searchPanel] = searchPanelBindings

        // Prompt context bindings
        var promptBindings: [KeyStroke: CommandID] = [:]
        promptBindings[KeyStroke(keyCode: Key.enter.rawValue)] = .promptConfirm
        promptBindings[KeyStroke(keyCode: Key.enterAlt.rawValue)] = .promptConfirm
        promptBindings[KeyStroke(keyCode: AsciiKey.escape)] = .promptCancel
        context[.prompt] = promptBindings

        // Context menu context bindings
        var contextMenuBindings: [KeyStroke: CommandID] = [:]
        contextMenuBindings[KeyStroke(keyCode: Key.up.rawValue)] = .contextMenuUp
        contextMenuBindings[KeyStroke(keyCode: Key.down.rawValue)] = .contextMenuDown
        contextMenuBindings[KeyStroke(keyCode: Key.enter.rawValue)] = .contextMenuSelect
        contextMenuBindings[KeyStroke(keyCode: Key.enterAlt.rawValue)] = .contextMenuSelect
        contextMenuBindings[KeyStroke(keyCode: AsciiKey.escape)] = .contextMenuDismiss
        context[.contextMenu] = contextMenuBindings

        // Apply config string overrides (Phase 3)
        Self.applyConfigOverrides(config: config, global: &global)

        // Multi-key sequence bindings (vim normal mode)
        var sequences: [KeyContext: [[KeyStroke]: CommandID]] = [:]
        var vimNormalSeqs: [[KeyStroke]: CommandID] = [:]
        let gKey = KeyStroke(keyCode: AsciiKey.g)
        let dKey = KeyStroke(keyCode: 0x64)  // 'd'
        let yKey = KeyStroke(keyCode: AsciiKey.y)
        vimNormalSeqs[[gKey, gKey]] = .vimGotoFirstLine
        vimNormalSeqs[[dKey, dKey]] = .vimDeleteLine
        vimNormalSeqs[[yKey, yKey]] = .vimYankLine
        sequences[.editorVimNormal] = vimNormalSeqs

        self.globalBindings = global
        self.contextBindings = context
        self.sequenceBindings = sequences
    }

    func resolve(_ stroke: KeyStroke, context: KeyContext, isRepeat: Bool = false) -> CommandID? {
        // Context-specific bindings checked first (fire on press and repeat)
        if let contextMap = contextBindings[context], let command = contextMap[stroke] {
            return command
        }
        // Global bindings only fire on press (not repeat)
        if !isRepeat {
            return globalBindings[stroke]
        }
        return nil
    }

    func resolveSequence(_ strokes: [KeyStroke], context: KeyContext) -> ResolveResult {
        guard let contextSeqs = sequenceBindings[context] else { return .none }

        if let command = contextSeqs[strokes] {
            return .command(command)
        }

        for seq in contextSeqs.keys {
            if seq.count > strokes.count && Array(seq.prefix(strokes.count)) == strokes {
                return .partial
            }
        }

        return .none
    }

    // MARK: - Label lookup (Phase 4)

    func shortcutLabel(for command: CommandID, context: KeyContext? = nil) -> String? {
        // Check context-specific bindings first
        if let ctx = context, let contextMap = contextBindings[ctx] {
            if let stroke = Self.preferredStroke(for: command, in: contextMap) {
                return KeyStrokeFormatter.label(for: stroke)
            }
        }
        // Check global bindings
        if let stroke = Self.preferredStroke(for: command, in: globalBindings) {
            return KeyStrokeFormatter.label(for: stroke)
        }
        return nil
    }

    /// Pick the best keystroke for a command, preferring .super > .meta > .ctrl for deterministic labels.
    private static func preferredStroke(
        for command: CommandID, in bindings: [KeyStroke: CommandID]
    ) -> KeyStroke? {
        let matches = bindings.filter { $0.value == command }.map(\.key)
        guard !matches.isEmpty else { return nil }
        return matches.sorted { a, b in
            modifierPriority(a.modifiers) < modifierPriority(b.modifiers)
        }.first
    }

    private static func modifierPriority(_ mods: KeyModifiers) -> Int {
        if mods.contains(.super) { return 0 }
        if mods.contains(.meta) { return 1 }
        if mods.contains(.ctrl) { return 2 }
        return 3
    }

    // MARK: - Status hints (Phase 4)

    func statusHints() -> String {
        let save = shortcutLabel(for: .saveFile) ?? "^O"
        let quit = shortcutLabel(for: .handleCtrlX) ?? "^X"
        return "\(save): Save, \(quit): Quit"
    }

    func openedStatusHints() -> String {
        let save = shortcutLabel(for: .saveFile) ?? "^O"
        let quit = shortcutLabel(for: .handleCtrlX) ?? "^X"
        return "\(save): Save, \(quit): Tree/Quit"
    }

    // MARK: - Default builders

    private static func buildNanoVimDefaults(
        config: KittyConfig, global: inout [KeyStroke: CommandID]
    ) {
        // Global hotkeys (Ctrl+key)
        global[KeyStroke(keyCode: AsciiKey.o, modifiers: .ctrl)] = .saveFile
        global[KeyStroke(keyCode: AsciiKey.n, modifiers: .ctrl)] = .newFile
        global[KeyStroke(keyCode: AsciiKey.b, modifiers: .ctrl)] = .toggleSidebar
        global[KeyStroke(keyCode: AsciiKey.h, modifiers: .ctrl)] = .cycleFileVisibility

        // Tab navigation
        global[KeyStroke(keyCode: Key.pageDown.rawValue, modifiers: .ctrl)] = .nextTab
        global[KeyStroke(keyCode: Key.pageUp.rawValue, modifiers: .ctrl)] = .previousTab

        // Ctrl+W close tab — only in nano mode
        if config.keybindingMode == .nano {
            global[KeyStroke(keyCode: AsciiKey.w, modifiers: .ctrl)] = .closeTab
        }

        // Search
        global[KeyStroke(keyCode: AsciiKey.f, modifiers: .ctrl)] = .searchOpenFile
        global[KeyStroke(keyCode: AsciiKey.f, modifiers: [.ctrl, .shift])] = .searchOpenWorkspace
        global[KeyStroke(keyCode: AsciiKey.f - 32, modifiers: [.ctrl, .shift])] = .searchOpenWorkspace

        // Clipboard shortcuts from configured modifier
        buildClipboardBindings(config: config, global: &global)

        // Ctrl+X always maps to handleCtrlX (dual behavior)
        global[KeyStroke(keyCode: AsciiKey.x, modifiers: .ctrl)] = .handleCtrlX

        // History shortcuts from configured modifier
        buildHistoryBindings(config: config, global: &global)

        // Escape and force quit
        global[KeyStroke(keyCode: AsciiKey.escape)] = .escapeEditor
        global[KeyStroke(keyCode: 3)] = .forceQuit
    }

    private static func buildKittyCodeDefaults(
        config: KittyConfig, global: inout [KeyStroke: CommandID]
    ) {
        // Primary: Cmd+key bindings
        global[KeyStroke(keyCode: AsciiKey.s, modifiers: .super)] = .saveFile
        global[KeyStroke(keyCode: AsciiKey.n, modifiers: .super)] = .newFile
        global[KeyStroke(keyCode: AsciiKey.w, modifiers: .super)] = .closeTab
        global[KeyStroke(keyCode: AsciiKey.b, modifiers: .super)] = .toggleSidebar

        // Ctrl fallbacks
        global[KeyStroke(keyCode: AsciiKey.o, modifiers: .ctrl)] = .saveFile
        global[KeyStroke(keyCode: AsciiKey.n, modifiers: .ctrl)] = .newFile
        global[KeyStroke(keyCode: AsciiKey.w, modifiers: .ctrl)] = .closeTab
        global[KeyStroke(keyCode: AsciiKey.b, modifiers: .ctrl)] = .toggleSidebar

        global[KeyStroke(keyCode: AsciiKey.h, modifiers: .ctrl)] = .cycleFileVisibility

        // Tab navigation
        global[KeyStroke(keyCode: Key.pageDown.rawValue, modifiers: .ctrl)] = .nextTab
        global[KeyStroke(keyCode: Key.pageUp.rawValue, modifiers: .ctrl)] = .previousTab

        // Clipboard: Cmd+C/V/X primary
        global[KeyStroke(keyCode: AsciiKey.c, modifiers: .super)] = .copy
        global[KeyStroke(keyCode: AsciiKey.c - 32, modifiers: .super)] = .copy
        global[KeyStroke(keyCode: AsciiKey.v, modifiers: .super)] = .paste
        global[KeyStroke(keyCode: AsciiKey.v - 32, modifiers: .super)] = .paste
        global[KeyStroke(keyCode: AsciiKey.x, modifiers: .super)] = .cut
        global[KeyStroke(keyCode: AsciiKey.x - 32, modifiers: .super)] = .cut

        // Search
        global[KeyStroke(keyCode: AsciiKey.f, modifiers: .super)] = .searchOpenFile
        global[KeyStroke(keyCode: AsciiKey.f - 32, modifiers: .super)] = .searchOpenFile
        global[KeyStroke(keyCode: AsciiKey.f, modifiers: .ctrl)] = .searchOpenFile
        global[KeyStroke(keyCode: AsciiKey.f, modifiers: [.super, .shift])] = .searchOpenWorkspace
        global[KeyStroke(keyCode: AsciiKey.f - 32, modifiers: [.super, .shift])] = .searchOpenWorkspace
        global[KeyStroke(keyCode: AsciiKey.f, modifiers: [.ctrl, .shift])] = .searchOpenWorkspace
        global[KeyStroke(keyCode: AsciiKey.f - 32, modifiers: [.ctrl, .shift])] = .searchOpenWorkspace

        // Replace
        global[KeyStroke(keyCode: AsciiKey.h, modifiers: .super)] = .searchToggleReplace
        global[KeyStroke(keyCode: AsciiKey.h - 32, modifiers: .super)] = .searchToggleReplace
        global[KeyStroke(keyCode: AsciiKey.h, modifiers: [.super, .shift])] = .searchToggleReplace
        global[KeyStroke(keyCode: AsciiKey.h - 32, modifiers: [.super, .shift])] = .searchToggleReplace

        // Also register clipboard from configured modifier (for fallback)
        buildClipboardBindings(config: config, global: &global)

        // Ctrl+X always maps to handleCtrlX (dual behavior)
        global[KeyStroke(keyCode: AsciiKey.x, modifiers: .ctrl)] = .handleCtrlX

        // History: Cmd+Z/Y primary
        global[KeyStroke(keyCode: AsciiKey.z, modifiers: .super)] = .undo
        global[KeyStroke(keyCode: AsciiKey.z - 32, modifiers: .super)] = .undo
        global[KeyStroke(keyCode: AsciiKey.y, modifiers: .super)] = .redo
        global[KeyStroke(keyCode: AsciiKey.y - 32, modifiers: .super)] = .redo
        global[KeyStroke(keyCode: AsciiKey.z, modifiers: [.super, .shift])] = .redo
        global[KeyStroke(keyCode: AsciiKey.z - 32, modifiers: [.super, .shift])] = .redo

        // Also register history from configured modifier (for fallback)
        buildHistoryBindings(config: config, global: &global)

        // Escape and force quit
        global[KeyStroke(keyCode: AsciiKey.escape)] = .escapeEditor
        global[KeyStroke(keyCode: 3)] = .forceQuit
    }

    private static func buildClipboardBindings(
        config: KittyConfig, global: inout [KeyStroke: CommandID]
    ) {
        let clipMod = config.keybindings.clipboardModifier
        for mods in modifiersFor(clipMod) {
            global[KeyStroke(keyCode: AsciiKey.c, modifiers: mods)] = .copy
            global[KeyStroke(keyCode: AsciiKey.c - 32, modifiers: mods)] = .copy

            global[KeyStroke(keyCode: AsciiKey.v, modifiers: mods)] = .paste
            global[KeyStroke(keyCode: AsciiKey.v - 32, modifiers: mods)] = .paste

            // Cut: only register if modifier is NOT control (Ctrl+X is handleCtrlX)
            if mods != .ctrl {
                global[KeyStroke(keyCode: AsciiKey.x, modifiers: mods)] = .cut
                global[KeyStroke(keyCode: AsciiKey.x - 32, modifiers: mods)] = .cut
            }
        }
    }

    private static func buildHistoryBindings(
        config: KittyConfig, global: inout [KeyStroke: CommandID]
    ) {
        let histMod = config.keybindings.historyModifier
        for mods in modifiersFor(histMod) {
            global[KeyStroke(keyCode: AsciiKey.z, modifiers: mods)] = .undo
            global[KeyStroke(keyCode: AsciiKey.z - 32, modifiers: mods)] = .undo

            global[KeyStroke(keyCode: AsciiKey.y, modifiers: mods)] = .redo
            global[KeyStroke(keyCode: AsciiKey.y - 32, modifiers: mods)] = .redo

            global[KeyStroke(keyCode: AsciiKey.z, modifiers: mods.union(.shift))] = .redo
            global[KeyStroke(keyCode: AsciiKey.z - 32, modifiers: mods.union(.shift))] = .redo
        }
    }

    // MARK: - Config overrides (Phase 3)

    private static func applyConfigOverrides(
        config: KittyConfig, global: inout [KeyStroke: CommandID]
    ) {
        applyOverride(config.keybindings.tabNext, for: .nextTab, in: &global)
        applyOverride(config.keybindings.tabPrev, for: .previousTab, in: &global)
        applyOverride(config.keybindings.toggleSidebar, for: .toggleSidebar, in: &global)
        if let tabClose = config.keybindings.tabClose {
            applyOverride(tabClose, for: .closeTab, in: &global)
        }

        // General overrides: "commandName": ["key1", "key2"]
        for (commandName, keyStrings) in config.keybindings.overrides {
            guard let command = CommandID(rawValue: commandName) else { continue }
            // Remove all existing bindings for this command
            global = global.filter { $0.value != command }
            // Add new bindings
            for keyString in keyStrings {
                if let parsed = KeyStrokeParser.parse(keyString) {
                    global[parsed] = command
                }
            }
        }
    }

    private static func applyOverride(
        _ keyString: String, for command: CommandID, in bindings: inout [KeyStroke: CommandID]
    ) {
        guard let parsed = KeyStrokeParser.parse(keyString) else { return }
        // Check if this is the default binding — if so, skip the override
        if bindings[parsed] == command { return }
        replaceBinding(for: command, with: parsed, in: &bindings)
    }

    private static func replaceBinding(
        for command: CommandID, with newStroke: KeyStroke, in bindings: inout [KeyStroke: CommandID]
    ) {
        bindings = bindings.filter { $0.value != command }
        bindings[newStroke] = command
    }

    private static func modifiersFor(
        _ modifier: KittyConfig.KeybindingsConfig.ShortcutModifier
    ) -> [KeyModifiers] {
        switch modifier {
        case .command:
            return [.super, .meta]
        case .control:
            return [.ctrl]
        case .both:
            return [.super, .meta, .ctrl]
        }
    }
}

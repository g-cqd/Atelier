import KittyCodecs

func isConfiguredCopyShortcut(_ key: KeyEvent, config: KittyConfig) -> Bool {
    matchesConfiguredShortcut(
        key,
        letter: AsciiKey.c,
        modifier: config.keybindings.clipboardModifier
    )
}

func isConfiguredCutShortcut(_ key: KeyEvent, config: KittyConfig) -> Bool {
    matchesConfiguredShortcut(
        key,
        letter: AsciiKey.x,
        modifier: config.keybindings.clipboardModifier
    )
}

func isConfiguredPasteShortcut(_ key: KeyEvent, config: KittyConfig) -> Bool {
    matchesConfiguredShortcut(
        key,
        letter: AsciiKey.v,
        modifier: config.keybindings.clipboardModifier
    )
}

func isConfiguredUndoShortcut(_ key: KeyEvent, config: KittyConfig) -> Bool {
    matchesConfiguredShortcut(
        key,
        letter: AsciiKey.z,
        modifier: config.keybindings.historyModifier
    )
}

func isConfiguredRedoShortcut(_ key: KeyEvent, config: KittyConfig) -> Bool {
    matchesConfiguredShortcut(
        key,
        letter: AsciiKey.y,
        modifier: config.keybindings.historyModifier
    ) || matchesConfiguredShortcut(
        key,
        letter: AsciiKey.z,
        modifier: config.keybindings.historyModifier,
        requiresShift: true
    )
}

private func matchesConfiguredShortcut(
    _ key: KeyEvent,
    letter: UInt32,
    modifier: KittyConfig.KeybindingsConfig.ShortcutModifier,
    requiresShift: Bool = false
) -> Bool {
    guard matchesShortcutKey(key, letter: letter) else {
        return false
    }

    let normalizedModifiers = normalizedShortcutModifiers(key.modifiers)
    return expectedShortcutModifiers(for: modifier, requiresShift: requiresShift).contains(normalizedModifiers)
}

private func matchesShortcutKey(_ key: KeyEvent, letter: UInt32) -> Bool {
    key.keyCode == letter || key.keyCode == letter - 32
}

private func normalizedShortcutModifiers(_ modifiers: KeyModifiers) -> KeyModifiers {
    modifiers.subtracting([.capsLock, .numLock])
}

private func expectedShortcutModifiers(
    for modifier: KittyConfig.KeybindingsConfig.ShortcutModifier,
    requiresShift: Bool
) -> [KeyModifiers] {
    let baseModifiers: [KeyModifiers] = switch modifier {
    case .command:
        [.super, .meta]
    case .control:
        [.ctrl]
    case .both:
        [.super, .meta, .ctrl]
    }

    if requiresShift {
        return baseModifiers.map { $0.union(.shift) }
    }

    return baseModifiers
}

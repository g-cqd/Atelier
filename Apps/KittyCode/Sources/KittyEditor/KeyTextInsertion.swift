import AtelierText
public import KittyCodecs

private let blockedTextInsertionModifiers: KeyModifiers = [.ctrl, .super, .hyper, .meta]

public func textInsertion(for key: KeyEvent, allowTab: Bool = false) -> String? {
    guard key.modifiers.intersection(blockedTextInsertionModifiers).isEmpty else {
        return nil
    }

    if !key.associatedText.isEmpty {
        return key.associatedText
    }

    if allowTab, key.keyCode == 9 {
        return "\t"
    }

    // Reject Unicode Private Use Area (0xE000-0xF8FF) which includes
    // kitty protocol functional keys (arrows, home, end, page up/down, etc.)
    if key.keyCode >= 0xE000 && key.keyCode <= 0xF8FF {
        return nil
    }

    guard let scalar = UnicodeScalar(key.keyCode) else {
        return nil
    }

    let character = Character(scalar)
    return character.isPrintable ? String(character) : nil
}

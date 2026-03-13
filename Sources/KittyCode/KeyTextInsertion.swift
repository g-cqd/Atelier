import KittyCodecs
import KittyText

private let blockedTextInsertionModifiers: KeyModifiers = [.ctrl, .super, .hyper, .meta]

func textInsertion(for key: KeyEvent, allowTab: Bool = false) -> String? {
    guard key.modifiers.intersection(blockedTextInsertionModifiers).isEmpty else {
        return nil
    }

    if !key.associatedText.isEmpty {
        return key.associatedText
    }

    if allowTab, key.keyCode == 9 {
        return "\t"
    }

    guard let scalar = UnicodeScalar(key.keyCode) else {
        return nil
    }

    let character = Character(scalar)
    return character.isPrintable ? String(character) : nil
}

import AemiKernel
import Foundation
import KittyCodecs
import KittyInput

public enum KeyStrokeParser {
    public static func parse(_ string: String) -> KeyStroke? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let tokens = trimmed.lowercased().split(separator: "+").map(String.init)
        guard !tokens.isEmpty else { return nil }

        var modifiers: KeyModifiers = []
        var keyToken: String?

        for token in tokens {
            switch token {
                case "ctrl", "control":
                    modifiers.insert(.ctrl)
                case "cmd", "command", "super":
                    modifiers.insert(.super)
                case "alt", "option":
                    modifiers.insert(.alt)
                case "shift":
                    modifiers.insert(.shift)
                case "meta":
                    modifiers.insert(.meta)
                default:
                    // Last non-modifier token is the key
                    if keyToken != nil {
                        return nil  // Multiple key tokens = invalid
                    }
                    keyToken = token
            }
        }

        guard let key = keyToken else { return nil }

        if let keyCode = specialKeyCode(key) {
            return KeyStroke(keyCode: keyCode, modifiers: modifiers)
        }

        // Single letter a-z
        if key.count == 1, let char = key.first, let byte = char.asciiValue, ASCII.isLowercase(byte) {
            return KeyStroke(keyCode: UInt32(byte), modifiers: modifiers)
        }

        // Single digit 0-9
        if key.count == 1, let char = key.first, let byte = char.asciiValue, ASCII.isDigit(byte) {
            return KeyStroke(keyCode: UInt32(byte), modifiers: modifiers)
        }

        return nil
    }

    private static func specialKeyCode(_ token: String) -> UInt32? {
        switch token {
            case "pagedown": return Key.pageDown.rawValue
            case "pageup": return Key.pageUp.rawValue
            case "enter", "return": return Key.enter.rawValue
            case "home": return Key.home.rawValue
            case "end": return Key.end.rawValue
            case "backspace": return Key.backspace.rawValue
            case "esc", "escape": return AsciiKey.escape
            case "tab": return Key.tab.rawValue
            case "space": return UInt32(Character(" ").asciiValue!)
            case "up": return Key.up.rawValue
            case "down": return Key.down.rawValue
            case "left": return Key.left.rawValue
            case "right": return Key.right.rawValue
            default: return nil
        }
    }
}

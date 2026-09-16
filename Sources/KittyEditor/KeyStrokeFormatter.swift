import Foundation
import KittyCodecs
import KittyInput

public enum KeyStrokeFormatter {
    public static func label(for stroke: KeyStroke) -> String {
        var parts: [String] = []

        // Modifiers in canonical order: Ctrl, Alt, Shift, Cmd, Meta
        if stroke.modifiers.contains(.ctrl) { parts.append("Ctrl") }
        if stroke.modifiers.contains(.alt) { parts.append("Alt") }
        if stroke.modifiers.contains(.shift) { parts.append("Shift") }
        if stroke.modifiers.contains(.super) { parts.append("Cmd") }
        if stroke.modifiers.contains(.meta) { parts.append("Meta") }

        parts.append(keyName(stroke.keyCode))
        return parts.joined(separator: "+")
    }

    private static func keyName(_ keyCode: UInt32) -> String {
        // Special keys
        if keyCode == Key.pageDown.rawValue { return "PageDown" }
        if keyCode == Key.pageUp.rawValue { return "PageUp" }
        if keyCode == Key.enter.rawValue || keyCode == Key.enterAlt.rawValue { return "Enter" }
        if keyCode == Key.home.rawValue { return "Home" }
        if keyCode == Key.end.rawValue { return "End" }
        if keyCode == Key.backspace.rawValue || keyCode == Key.backspaceAlt.rawValue {
            return "Backspace"
        }
        if keyCode == AsciiKey.escape { return "Esc" }
        if keyCode == Key.up.rawValue { return "Up" }
        if keyCode == Key.down.rawValue { return "Down" }
        if keyCode == Key.left.rawValue { return "Left" }
        if keyCode == Key.right.rawValue { return "Right" }

        // Lowercase ASCII letter (a-z)
        if keyCode >= 0x61 && keyCode <= 0x7A {
            return String(UnicodeScalar(keyCode - 32)!)  // Uppercase
        }

        // Uppercase ASCII letter (A-Z)
        if keyCode >= 0x41 && keyCode <= 0x5A {
            return String(UnicodeScalar(keyCode)!)
        }

        return String(format: "0x%X", keyCode)
    }
}

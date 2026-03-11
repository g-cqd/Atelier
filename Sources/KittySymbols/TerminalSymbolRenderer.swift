import Foundation

public enum TerminalSymbolRenderer {
    public static func label(_ glyph: TerminalSymbolTheme.Glyph, _ text: String) -> String {
        guard !glyph.text.isEmpty else {
            return text
        }
        return "\(glyph.text) \(text)"
    }
}

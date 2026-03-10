/// Terminal display-width utilities for Unicode characters and strings.
///
/// Uses the East Asian Width property and Unicode general categories to
/// determine how many terminal columns a character occupies.
public enum UnicodeWidth {
    /// Returns the number of terminal columns needed to display `char`.
    ///
    /// - Returns: `0` for null and default-ignorable code points,
    ///   `2` for wide/CJK characters, `1` for everything else.
    public static func displayWidth(of char: Character) -> Int {
        guard let scalar = char.unicodeScalars.first else { return 0 }
        if scalar.value == 0 { return 0 }
        if scalar.properties.isDefaultIgnorableCodePoint { return 0 }
        if isCJKOrWide(scalar) { return 2 }
        return 1
    }

    /// Returns the total number of terminal columns needed to display `string`.
    public static func displayWidth(of string: String) -> Int {
        string.reduce(0) { $0 + displayWidth(of: $1) }
    }

    private static func isCJKOrWide(_ scalar: Unicode.Scalar) -> Bool {
        let v = scalar.value
        return (0x1100...0x115F).contains(v) ||   // Hangul Jamo
               (0x2E80...0x303E).contains(v) ||   // CJK Radicals / Kangxi
               (0x3041...0x33BF).contains(v) ||   // Hiragana, Katakana, Bopomofo, etc.
               (0x3400...0x4DBF).contains(v) ||   // CJK Extension A
               (0x4E00...0x9FFF).contains(v) ||   // CJK Unified Ideographs
               (0xA000...0xA4CF).contains(v) ||   // Yi Syllables
               (0xAC00...0xD7AF).contains(v) ||   // Hangul Syllables
               (0xF900...0xFAFF).contains(v) ||   // CJK Compatibility Ideographs
               (0xFE30...0xFE6F).contains(v) ||   // CJK Compatibility Forms
               (0xFF01...0xFF60).contains(v) ||   // Fullwidth Latin / Katakana
               (0xFFE0...0xFFE6).contains(v) ||   // Fullwidth Signs
               (0x20000...0x2FFFD).contains(v) || // CJK Extension B–F
               (0x30000...0x3FFFD).contains(v)    // CJK Extension G+
    }
}

/// Terminal display-width utilities for Unicode characters and strings.
///
/// Uses the East Asian Width property and Unicode general categories to
/// determine how many terminal columns a character occupies.
public enum UnicodeWidth {
    /// Returns the number of terminal columns needed to display `char`.
    ///
    /// - Returns: `0` for null and default-ignorable code points,
    ///   `2` for wide/CJK characters, `1` for everything else.
    @inline(__always)
    public static func displayWidth(of char: Character) -> Int {
        guard let scalar = char.unicodeScalars.first else { return 0 }
        let v = scalar.value
        if v == 0 { return 0 }
        // ASCII fast path: covers ~99% of typical source code
        if v < 0x1100 { return 1 }
        if scalar.properties.isDefaultIgnorableCodePoint { return 0 }
        if isCJKOrWide(v) { return 2 }
        return 1
    }

    /// Returns the total number of terminal columns needed to display `string`.
    public static func displayWidth(of string: String) -> Int {
        var total = 0
        for char in string {
            total &+= displayWidth(of: char)
        }
        return total
    }

    // Sorted array of (start, end) ranges for binary search
    private static let wideRanges: [(UInt32, UInt32)] = [
        (0x1100, 0x115F),  // Hangul Jamo
        (0x2E80, 0x303E),  // CJK Radicals / Kangxi
        (0x3041, 0x33BF),  // Hiragana, Katakana, Bopomofo, etc.
        (0x3400, 0x4DBF),  // CJK Extension A
        (0x4E00, 0x9FFF),  // CJK Unified Ideographs
        (0xA000, 0xA4CF),  // Yi Syllables
        (0xAC00, 0xD7AF),  // Hangul Syllables
        (0xF900, 0xFAFF),  // CJK Compatibility Ideographs
        (0xFE30, 0xFE6F),  // CJK Compatibility Forms
        (0xFF01, 0xFF60),  // Fullwidth Latin / Katakana
        (0xFFE0, 0xFFE6),  // Fullwidth Signs
        (0x20000, 0x2FFFD),  // CJK Extension B-F
        (0x30000, 0x3FFFD),  // CJK Extension G+
    ]

    /// Binary search over sorted wide ranges.
    private static func isCJKOrWide(_ v: UInt32) -> Bool {
        var lo = 0
        var hi = wideRanges.count - 1
        while lo <= hi {
            let mid = (lo + hi) >> 1
            let range = wideRanges[mid]
            if v < range.0 {
                hi = mid - 1
            } else if v > range.1 {
                lo = mid + 1
            } else {
                return true
            }
        }
        return false
    }
}

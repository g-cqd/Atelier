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
        let scalars = char.unicodeScalars
        guard let firstScalar = scalars.first else { return 0 }
        if firstScalar.value == 0 { return 0 }
        if isEmojiCluster(scalars) { return 2 }
        if scalars.count == 1 {
            if firstScalar.value < 0x1100 { return 1 }
            if firstScalar.properties.isDefaultIgnorableCodePoint { return 0 }
            if isCJKOrWide(firstScalar.value) { return 2 }
            return 1
        }

        for scalar in scalars where !scalar.properties.isDefaultIgnorableCodePoint {
            if isCJKOrWide(scalar.value) { return 2 }
            return 1
        }

        if firstScalar.properties.isDefaultIgnorableCodePoint { return 0 }
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
    private static func isCJKOrWide(_ value: UInt32) -> Bool {
        var lowerBound = 0
        var upperBound = wideRanges.count - 1
        while lowerBound <= upperBound {
            let mid = (lowerBound + upperBound) >> 1
            let range = wideRanges[mid]
            if value < range.0 {
                upperBound = mid - 1
            } else if value > range.1 {
                lowerBound = mid + 1
            } else {
                return true
            }
        }
        return false
    }

    private static func isEmojiCluster(_ scalars: String.UnicodeScalarView) -> Bool {
        if scalars.contains(where: { $0.properties.isEmojiPresentation }) {
            return true
        }
        return scalars.count > 1 && scalars.contains(where: { $0.properties.isEmoji })
    }
}

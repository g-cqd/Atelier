/// Terminal display-width utilities for Unicode characters and strings.
///
/// Width determination follows Unicode UAX #11 East Asian Width and the
/// Extended Pictographic / Emoji_Presentation properties for emoji clusters.
/// CJKV ideograph detection delegates to `Unicode.Scalar.Properties.isIdeographic`,
/// so the only hand-maintained data is a small table of wide ranges Unicode
/// classifies as East Asian Wide but are not ideographs (Hangul, Kana,
/// fullwidth forms, Yi syllables).
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

        // ASCII / Latin-Extended fast path: single-scalar values below the
        // first wide-eligible range are unconditionally narrow.
        if scalars.count == 1, firstScalar.value < 0x1100 {
            return 1
        }

        if isEmojiCluster(scalars) { return 2 }

        if scalars.count == 1 {
            if firstScalar.properties.isDefaultIgnorableCodePoint { return 0 }
            return isWide(firstScalar) ? 2 : 1
        }

        // Multi-scalar: width is determined by the first non-ignorable base.
        for scalar in scalars where !scalar.properties.isDefaultIgnorableCodePoint {
            return isWide(scalar) ? 2 : 1
        }

        return firstScalar.properties.isDefaultIgnorableCodePoint ? 0 : 1
    }

    /// Returns the total number of terminal columns needed to display `string`.
    public static func displayWidth(of string: String) -> Int {
        var total = 0
        for char in string {
            total &+= displayWidth(of: char)
        }
        return total
    }

    /// Wide ranges that Unicode classifies as East Asian Wide but that
    /// `Unicode.Scalar.Properties.isIdeographic` does not cover.
    ///
    /// The CJK Unified Ideographs blocks (4E00–9FFF, Extensions A–H including
    /// SMP planes 20000–3FFFD) and CJK Compatibility Ideographs (F900–FAFF)
    /// are detected via `isIdeographic`. Kangxi Radicals and CJK Radicals
    /// Supplement are East Asian Wide but not Ideographic, so they stay here.
    private static let residualWideRanges: [(UInt32, UInt32)] = [
        (0x1100, 0x115F),  // Hangul Jamo
        (0x2E80, 0x303E),  // CJK Radicals + Kangxi + IDCs + CJK Symbols & Punctuation
        (0x3041, 0x33BF),  // Hiragana, Katakana, Bopomofo, Hangul Compat Jamo, …
        (0xA000, 0xA4CF),  // Yi Syllables
        (0xAC00, 0xD7AF),  // Hangul Syllables
        (0xFE30, 0xFE6F),  // CJK Compatibility Forms
        (0xFF01, 0xFF60),  // Fullwidth Latin & Katakana
        (0xFFE0, 0xFFE6)  // Fullwidth Signs
    ]

    @inline(__always)
    private static func isWide(_ scalar: Unicode.Scalar) -> Bool {
        // Native CJKV detection covers the largest ranges by far (Unified
        // Ideographs, every CJK Extension, Kangxi Radicals, Compat Ideographs).
        if scalar.properties.isIdeographic { return true }
        return isInResidualWideTable(scalar.value)
    }

    /// Binary search over the residual sorted wide ranges.
    private static func isInResidualWideTable(_ value: UInt32) -> Bool {
        var lowerBound = 0
        var upperBound = residualWideRanges.count - 1
        while lowerBound <= upperBound {
            let mid = (lowerBound + upperBound) >> 1
            let range = residualWideRanges[mid]
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

    @inline(__always)
    private static func isEmojiCluster(_ scalars: String.UnicodeScalarView) -> Bool {
        if scalars.contains(where: { $0.properties.isEmojiPresentation }) {
            return true
        }
        return scalars.count > 1 && scalars.contains(where: { $0.properties.isEmoji })
    }
}

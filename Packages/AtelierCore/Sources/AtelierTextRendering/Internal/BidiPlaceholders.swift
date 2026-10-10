/// The placeholders a row draws for the bidi controls under ``BidiPolicy/forceLeftToRight``. The mapping mirrors
/// GitDiffViewer's `BidiControls.placeholder(for:)`, which the diff panes use: the app replaces the controls before its
/// text reaches this engine, so this mapping serves other callers and never changes the app's own text.
enum BidiPlaceholders {
    /// The placeholder drawn for `scalar`, or nil when `scalar` is not a bidi control. Every control and every
    /// placeholder is one UTF-16 unit, so substituting one for the other keeps every offset into the row.
    private static func placeholder(for scalar: Unicode.Scalar) -> Unicode.Scalar? {
        switch scalar.value {
            case 0x202A, 0x202D, 0x2066, 0x200E: "\u{25B8}"
            case 0x202B, 0x202E, 0x2067, 0x200F, 0x061C: "\u{25C2}"
            case 0x2068: "\u{2194}"
            case 0x202C, 0x2069: "\u{25A1}"
            default: nil
        }
    }

    /// `string` with each bidi control replaced by its placeholder, unit for unit, so its UTF-16 offsets are unchanged;
    /// `string` itself when it holds no control.
    /// - Complexity: O(`string`'s length in scalars).
    static func replacingControls(in string: String) -> String {
        guard string.unicodeScalars.contains(where: { placeholder(for: $0) != nil }) else { return string }
        var shown = String.UnicodeScalarView()
        for scalar in string.unicodeScalars {
            shown.append(placeholder(for: scalar) ?? scalar)
        }
        return String(shown)
    }
}

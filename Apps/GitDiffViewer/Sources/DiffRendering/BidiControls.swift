import AppKit
package import Foundation

/// The bidi controls a pane shows as visible placeholders, so that it never shows code other than what compiles (the
/// Trojan Source class, CVE-2021-42574).
///
/// They are Unicode's `Bidi_Control` characters: the embeddings and overrides LRE, RLE, LRO and RLO, with PDF that
/// ends them (U+202A to U+202E); the isolates LRI, RLI and FSI, with PDI that ends them (U+2066 to U+2069); and the
/// marks LRM, RLM and ALM (U+200E, U+200F, U+061C). All of them are invisible, and the first two kinds reorder the
/// text around them: drawn as it is, `abc⟨RLO⟩def⟨PDF⟩ghi` shows as `abcfedghi`.
///
/// A control shows as a character that the system's monospaced font and most coding fonts hold, one column wide and
/// one UTF-16 unit for one, so every offset into a row, the ones hover, intraline emphasis and findings use among them,
/// stays the source's:
/// - `▸` for a control that sets left to right: LRE, LRO, LRI and LRM;
/// - `◂` for one that sets right to left: RLE, RLO, RLI, RLM and ALM;
/// - `↔` for FSI, which takes the direction of what it isolates;
/// - `□` for PDF and PDI.
///
/// The placeholders are neutral characters rather than controls, so they reorder nothing: the text above shows as
/// `abc◂def□ghi`. Each is dimmed on a tinted chip, with no tooltip, and records the control it stands for under
/// `NSAttributedString.Key.diffBidiControl`, which copying writes back.
package enum BidiControls {
    /// The placeholder a pane shows for `scalar`, or nil when `scalar` is not a bidi control.
    package static func placeholder(for scalar: Unicode.Scalar) -> Unicode.Scalar? {
        switch scalar.value {
            case 0x202A, 0x202D, 0x2066, 0x200E: "\u{25B8}"
            case 0x202B, 0x202E, 0x2067, 0x200F, 0x061C: "\u{25C2}"
            case 0x2068: "\u{2194}"
            case 0x202C, 0x2069: "\u{25A1}"
            default: nil
        }
    }

    /// How a placeholder is drawn in a text drawn with `palette`: dimmed like secondary text, on a chip of the system's
    /// orange, which no row colour, intraline change or finding uses, strong enough to show on a removed row's red.
    static func placeholderStyle(palette: DiffPalette) -> [NSAttributedString.Key: Any] {
        [
            .foregroundColor: palette.textColor.withAlphaComponent(0.7),
            .backgroundColor: NSColor.systemOrange.withAlphaComponent(0.45)
        ]
    }

    /// The placeholders of a text assembled row by row: where each lies, and the control it stands for.
    struct Placeholders {
        private(set) var controls: [(range: NSRange, control: Unicode.Scalar)] = []

        /// `line` as a row starting at UTF-16 `offset` shows it, each bidi control replaced by its placeholder and
        /// recorded here; `line` itself when it holds none.
        /// - Complexity: O(`line`'s UTF-8 length).
        mutating func reveal(_ line: Substring, at offset: Int) -> Substring {
            guard Self.holdsControl(line) else { return line }
            var shown = String.UnicodeScalarView()
            var column = 0
            for scalar in line.unicodeScalars {
                if let placeholder = placeholder(for: scalar) {
                    controls.append((NSRange(location: offset + column, length: 1), scalar))
                    shown.append(placeholder)
                } else {
                    shown.append(scalar)
                }
                column += scalar.utf16.count
            }
            return Substring(String(shown))
        }

        /// Styles and records each placeholder of `text`, the assembled text, drawn with `palette`.
        func apply(to text: NSMutableAttributedString, palette: DiffPalette) {
            guard !controls.isEmpty else { return }
            let style = placeholderStyle(palette: palette)
            for (range, control) in controls {
                text.addAttributes(style, range: range)
                text.addAttribute(.diffBidiControl, value: String(control), range: range)
            }
        }

        /// Whether `line` holds a bidi control, looked for in its UTF-8 bytes: E2 80 8E or 8F (LRM, RLM), E2 80 AA to AE
        /// (LRE to RLO), E2 81 A6 to A9 (LRI to PDI) and D8 9C (ALM). `memchr` finds the lead bytes at memory speed,
        /// whatever the build's optimization, and most rows hold neither.
        private static func holdsControl(_ line: Substring) -> Bool {
            line.utf8.withContiguousStorageIfAvailable { bytes in
                holds(0xE2, in: bytes) { second, third in
                    second == 0x80 && (0x8E ... 0x8F ~= third || 0xAA ... 0xAE ~= third)
                        || second == 0x81 && 0xA6 ... 0xA9 ~= third
                } || holds(0xD8, in: bytes) { second, _ in second == 0x9C }
            } ?? line.unicodeScalars.contains { placeholder(for: $0) != nil }
        }

        /// Whether `bytes` hold `lead` with the two bytes after it, zero past the end, accepted by `continues`.
        private static func holds(
            _ lead: UInt8, in bytes: UnsafeBufferPointer<UInt8>, followedBy continues: (UInt8, UInt8) -> Bool
        ) -> Bool {
            guard let start = bytes.baseAddress.map(UnsafeRawPointer.init) else { return false }
            var index = 0
            while index < bytes.count, let found = memchr(start + index, Int32(lead), bytes.count - index) {
                let at = start.distance(to: UnsafeRawPointer(found))
                let second = at + 1 < bytes.count ? bytes[at + 1] : 0
                let third = at + 2 < bytes.count ? bytes[at + 2] : 0
                if continues(second, third) { return true }
                index = at + 1
            }
            return false
        }
    }
}

extension NSAttributedString.Key {
    /// On a placeholder the renderer shows for a bidi control: that control, as a `String` of its one scalar.
    package static let diffBidiControl = NSAttributedString.Key("GitDiffViewer.diffBidiControl")
}

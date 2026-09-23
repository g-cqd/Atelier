package import AppKit
import DiffCore
import Foundation

/// Colors a source snippet, such as a hover's declaration, the way a diff pane would: the lexical highlighting tier
/// mapped through the pane's ``DiffPalette``.
package enum CodeAttributedBuilder {
    /// `code` colored over `palette`'s font and text color, lexed as the fence's `languageTag`; an unrecognized or
    /// missing tag lexes as Swift.
    package static func attributedString(
        for code: String, languageTag: String? = nil, palette: DiffPalette
    ) -> NSAttributedString {
        guard !code.isEmpty else { return NSAttributedString() }
        let language = languageTag.flatMap { Language(name: $0) } ?? .swift
        let result = NSMutableAttributedString(
            string: code, attributes: [.font: palette.font, .foregroundColor: palette.textColor])
        guard language != .plain else { return result }
        let utf16Length = (code as NSString).length
        let units = Array(code.utf16)
        let tokens = LexicalHighlightEngine().highlight(utf16: units, language: language)
        result.beginEditing()
        for token in tokens {
            let range = NSRange(location: token.byteRange.lowerBound, length: token.byteRange.count)
            guard range.location >= 0, range.location + range.length <= utf16Length else { continue }
            result.addAttribute(.foregroundColor, value: palette.color(for: token.role), range: range)
        }
        result.endEditing()
        return result
    }
}

package import AppKit
import DiffCore
import Foundation

/// Colors a snippet of source (a fenced declaration in a hover document, typically) the same way a diff pane
/// would: the lexical tier of the highlighting engine, mapped through the pane's own ``DiffPalette``, so a
/// declaration shown in the hover panel matches the identifier it documents exactly.
package enum CodeAttributedBuilder {
    /// `code` colored over `palette`'s font and text color. `languageTag` is a fence's own language tag (`swift`,
    /// `objc`, `c++`, ...); an unrecognized or missing tag falls back to Swift, since nearly every fenced
    /// declaration a hover shows is Swift regardless of the tag sourcekit-lsp happened to put on the fence.
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

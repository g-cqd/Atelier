import AppKit
import AtelierSyntaxModel
import Foundation
import Testing

@testable import DiffRendering

@Suite struct CodeAttributedBuilderTests {
    private let palette = DiffPalette.system

    /// The color at UTF-16 offset `offset` of `attributed`.
    private func color(in attributed: NSAttributedString, at offset: Int) -> NSColor? {
        attributed.attribute(.foregroundColor, at: offset, effectiveRange: nil) as? NSColor
    }

    @Test func keywordStringAndCommentSpansGetDistinctColorsFromThePalette() {
        let code = "// a comment\nlet name = \"hello\""
        let attributed = CodeAttributedBuilder.attributedString(for: code, languageTag: "swift", palette: palette)

        let commentOffset = 0
        let keywordOffset = code.utf16Distance(of: "let")
        let stringOffset = code.utf16Distance(of: "\"hello\"") + 1

        let commentColor = color(in: attributed, at: commentOffset)
        let keywordColor = color(in: attributed, at: keywordOffset)
        let stringColor = color(in: attributed, at: stringOffset)

        #expect(commentColor == palette.color(for: .comment))
        #expect(keywordColor == palette.color(for: .keyword))
        #expect(stringColor == palette.color(for: .string))
        #expect(commentColor != keywordColor)
        #expect(keywordColor != stringColor)
    }

    @Test func plainTextCarriesThePalettesBaseTextColorThroughout() {
        let code = "no keywords here at all"
        let attributed = CodeAttributedBuilder.attributedString(for: code, languageTag: "swift", palette: palette)
        #expect(color(in: attributed, at: 0) == palette.textColor)
    }

    @Test func anUnrecognizedLanguageTagFallsBackToSwift() {
        let code = "let value = 1"
        let attributed = CodeAttributedBuilder.attributedString(
            for: code, languageTag: "not-a-real-language", palette: palette)
        let keywordOffset = code.utf16Distance(of: "let")
        #expect(color(in: attributed, at: keywordOffset) == palette.color(for: .keyword))
    }

    @Test func aMissingLanguageTagAlsoFallsBackToSwift() {
        let code = "let value = 1"
        let attributed = CodeAttributedBuilder.attributedString(for: code, palette: palette)
        let keywordOffset = code.utf16Distance(of: "let")
        #expect(color(in: attributed, at: keywordOffset) == palette.color(for: .keyword))
    }

    @Test func emptyCodeProducesAnEmptyAttributedString() {
        let attributed = CodeAttributedBuilder.attributedString(for: "", languageTag: "swift", palette: palette)
        #expect(attributed.length == 0)
    }
}

extension String {
    /// The UTF-16 offset of the first occurrence of `substring`.
    fileprivate func utf16Distance(of substring: String) -> Int {
        guard let range = range(of: substring) else { return 0 }
        return utf16.distance(from: utf16.startIndex, to: range.lowerBound.samePosition(in: utf16)!)
    }
}

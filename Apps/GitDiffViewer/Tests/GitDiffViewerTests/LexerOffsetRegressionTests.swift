import AppKit
import DiffCore
import Testing

@testable import DiffRendering

/// Token colours land on the UTF-16 ranges the UTF-16 scanner gave them before the lexer moved to UTF-8, whatever
/// the characters before them: accents, surrogate pairs, CJK, combining marks, tabs and bidi placeholders.
struct LexerOffsetRegressionTests {
    private static let old = """
        let café = "é" // ✓ done
        let emoji = "🙂🙂"; let n = 42 // 👍 two units each
        let 変数 = 0x1F /* 注释 */ + 1.5e3
        \tlet tab = "\\u{1F600}" // escaped, after a tab
        let e\u{301}te\u{301} = true // combining accents
        let rlo = "\u{202E}abc\u{202C}" // bidi controls show as placeholders
        @MainActor func f() -> Int { return 1 }
        """
    private static let new = old.replacingOccurrences(of: "42", with: "43")
        .replacingOccurrences(of: "func f() -> Int { return 1 }", with: "func g() -> Int { return 2 }")

    /// The colour runs of the unified pane of this diff, pinned from the UTF-16 scanner of commit 384d6e1.
    private static let pinnedRuns: [String] = [
        "0+3:keyword", "3+8:text", "11+3:string", "14+1:text", "15+9:comment", "24+1:text", "25+3:keyword",
        "28+9:text", "37+6:string", "43+2:text", "45+3:keyword", "48+5:text", "53+2:number", "55+1:text",
        "56+20:comment", "76+1:text", "77+3:keyword", "80+9:text", "89+6:string", "95+2:text", "97+3:keyword",
        "100+5:text", "105+2:number", "107+1:text", "108+20:comment", "128+1:text", "129+3:keyword", "132+6:text",
        "138+4:number", "142+1:text", "143+8:comment", "151+3:text", "154+5:number", "159+2:text", "161+3:keyword",
        "164+7:text", "171+11:string", "182+1:text", "183+23:comment", "206+1:text", "207+3:keyword", "210+9:text",
        "219+4:keyword", "223+1:text", "224+20:comment", "244+1:text", "245+3:keyword", "248+7:text",
        "255+1:string", "256+1:other", "257+3:string", "260+1:other", "261+1:string", "262+1:text",
        "263+37:comment", "300+1:text", "301+10:attribute", "311+1:text", "312+4:keyword", "316+8:text",
        "324+3:type", "327+3:text", "330+6:keyword", "336+1:text", "337+1:number", "338+3:text",
        "341+10:attribute", "351+1:text", "352+4:keyword", "356+8:text", "364+3:type", "367+3:text",
        "370+6:keyword", "376+1:text", "377+1:number", "378+2:text"
    ]

    @Test
    func `token colours keep the utf16 ranges of the utf16 scanner on non ASCII lines`() throws {
        let rendered = DiffRenderer.render(oldText: Self.old, newText: Self.new, language: .swift)
        let unified = try #require(rendered.unified)
        #expect(Self.colourRuns(of: unified.attributed) == Self.pinnedRuns)
    }

    @Test
    func `plain files produce no lexical tokens`() {
        let text = "é\n🙂\n"
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let tokens = DiffRenderer.tokensByLine(text: text, lines: lines, language: .plain)
        #expect(tokens.count == lines.count)
        #expect(tokens.joined().isEmpty)
    }

    /// Each foreground colour run of `text` as `location+length:name`: `text` for the palette's text colour, else the
    /// first role drawn in the run's colour, else `other`, such as a bidi placeholder.
    private static func colourRuns(of text: NSAttributedString) -> [String] {
        let palette = DiffPalette.system
        var runs: [String] = []
        text.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            let color = value as? NSColor
            let role = HighlightRole.allCases.first { palette.color(for: $0) == color }.map { "\($0)" }
            let name = color == palette.textColor ? "text" : role ?? "other"
            runs.append("\(range.location)+\(range.length):\(name)")
        }
        return runs
    }
}

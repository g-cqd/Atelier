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

    /// CRLF endings, astral characters (four UTF-8 bytes, two UTF-16 units) and tokens that span lines: a block
    /// comment, a multi-line string, and an unterminated string and comment clipped at their lines' ends.
    private static let spanningOld = [
        "/* a block comment 🙂 that",
        "   spans 𝔘 three lines ✓ */ let a = \"𝒳\" // tail 👍",
        "let s = \"\"\"",
        "  multi 🙂 line",
        "  string 𝔘 é",
        "  \"\"\"; let n = 0x1F",
        "let 𝑥 = \"open 🙂",
        "/* unterminated 🙂 comment"
    ]
    .joined(separator: "\r\n")
    private static let spanningNew = spanningOld.replacingOccurrences(of: "0x1F", with: "0x2F")
        .replacingOccurrences(of: "multi 🙂 line", with: "multi 🙂🙂 line")

    /// The colour runs of the three panes of the spanning diff, pinned from the renderer of commit 47919dd, which moved
    /// each row's tokens to UTF-16 as it placed them.
    private static let spanningPinnedRuns: [RenderedSide: [String]] = [
        .unified: [
            "0+26:comment", "26+1:text", "27+28:comment", "55+1:text", "56+3:keyword", "59+5:text", "64+4:string",
            "68+1:text", "69+10:comment", "79+1:text", "80+3:keyword", "83+5:text", "88+3:string", "91+1:text",
            "92+15:string", "107+1:text", "108+17:string", "125+1:text", "126+13:string", "139+1:text", "140+5:string",
            "145+2:text", "147+3:keyword", "150+5:text", "155+4:number", "159+1:text", "160+5:string", "165+2:text",
            "167+3:keyword", "170+5:text", "175+4:number", "179+1:text", "180+3:keyword", "183+6:text", "189+8:string",
            "197+1:text", "198+26:comment"
        ],
        .old: [
            "0+26:comment", "26+1:text", "27+28:comment", "55+1:text", "56+3:keyword", "59+5:text", "64+4:string",
            "68+1:text", "69+10:comment", "79+1:text", "80+3:keyword", "83+5:text", "88+3:string", "91+1:text",
            "92+15:string", "107+1:text", "108+13:string", "121+1:text", "122+5:string", "127+2:text", "129+3:keyword",
            "132+5:text", "137+4:number", "141+1:text", "142+3:keyword", "145+6:text", "151+8:string", "159+1:text",
            "160+26:comment"
        ],
        .new: [
            "0+26:comment", "26+1:text", "27+28:comment", "55+1:text", "56+3:keyword", "59+5:text", "64+4:string",
            "68+1:text", "69+10:comment", "79+1:text", "80+3:keyword", "83+5:text", "88+3:string", "91+1:text",
            "92+17:string", "109+1:text", "110+13:string", "123+1:text", "124+5:string", "129+2:text", "131+3:keyword",
            "134+5:text", "139+4:number", "143+1:text", "144+3:keyword", "147+6:text", "153+8:string", "161+1:text",
            "162+26:comment"
        ]
    ]

    @Test
    func `token colours keep their utf16 ranges on CRLF lines, astral characters and tokens that span lines`() throws {
        let rendered = DiffRenderer.render(oldText: Self.spanningOld, newText: Self.spanningNew, language: .swift)
        let panes: [(RenderedSide, RenderedText?)] = [
            (.unified, rendered.unified), (.old, rendered.old), (.new, rendered.new)
        ]
        for (side, pane) in panes {
            let text = try #require(pane)
            #expect(Self.colourRuns(of: text.attributed) == Self.spanningPinnedRuns[side], "\(side)")
        }
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

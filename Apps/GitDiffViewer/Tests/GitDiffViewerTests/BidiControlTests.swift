import AppKit
import CoreText
import DiffCore
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// Bidi controls in rendered text: each shows as a visible placeholder at its own offset, the row lays out in logical
/// order, and hover and intraline emphasis keep the source's columns (Trojan Source, CVE-2021-42574).
@MainActor
struct BidiControlTests {
    private static let rlo = "\u{202E}"
    private static let pdf = "\u{202C}"
    /// `abc⟨RLO⟩def⟨PDF⟩ghi`, which the override shows as `abcfedghi` when drawn as it is.
    private static let overridden = "abc\(rlo)def\(pdf)ghi"
    /// Every bidi control: the embeddings, overrides and PDF, the isolates and PDI, then the marks LRM, RLM and ALM.
    private static let controls: [Unicode.Scalar] = [
        "\u{202A}", "\u{202B}", "\u{202C}", "\u{202D}", "\u{202E}", "\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}",
        "\u{200E}", "\u{200F}", "\u{061C}"
    ]

    private func rendered(_ line: String, language: Language = .plain) throws -> RenderedText {
        try #require(DiffRenderer.render(oldText: line + "\n", newText: line + "\n", language: language).new)
    }

    /// A text view set up the way a scrolling pane sets one up, with `rendered` laid out whole.
    private func paneTextView(showing rendered: RenderedText) throws -> NSTextView {
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.textContainerInset = NSSize(width: 0, height: DiffPaneMetrics.containerInset)
        let container = try #require(textView.textContainer)
        container.lineFragmentPadding = DiffPaneMetrics.lineFragmentPadding
        container.widthTracksTextView = false
        container.size = NSSize(width: 800, height: DiffPaneMetrics.unboundedExtent)
        try #require(textView.textContentStorage?.textStorage).setAttributedString(rendered.attributed)
        let layoutManager = try #require(textView.textLayoutManager)
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        return textView
    }

    /// The first line of the first row, as `layoutManager` laid it out.
    private func firstLine(in layoutManager: NSTextLayoutManager) throws -> NSTextLineFragment {
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        let fragment = try #require(layoutManager.textLayoutFragment(for: layoutManager.documentRange.location))
        return try #require(fragment.textLineFragments.first)
    }

    /// Where the caret before each UTF-16 unit of `line`'s characters sits, and after the last one.
    private func caretOffsets(of line: NSTextLineFragment) -> [CGFloat] {
        (0 ... line.characterRange.length).map { line.locationForCharacter(at: $0).x }
    }

    /// The width of one column of the pane's font.
    private func columnWidth(of rendered: RenderedText) -> CGFloat {
        ("0" as NSString).size(withAttributes: [.font: rendered.palette.font]).width
    }

    /// The middle of `column` on the first row, in the text view's coordinates.
    private func point(column: Int, in rendered: RenderedText) -> NSPoint {
        NSPoint(
            x: DiffPaneMetrics.lineFragmentPadding + (CGFloat(column) + 0.5) * columnWidth(of: rendered),
            y: DiffPaneMetrics.containerInset + 0.5 * rendered.lineHeight)
    }

    // MARK: The rendered text

    @Test
    func `a bidi control shows as a placeholder at its own offset`() throws {
        let rendered = try rendered(Self.overridden)

        #expect(rendered.attributed.string == "abc\u{25C2}def\u{25A1}ghi")
    }

    @Test
    func `every bidi control shows as a placeholder, the marks among them`() throws {
        let line = Self.controls.map { "x" + String($0) }.joined()
        let rendered = try rendered(line)

        let string = rendered.attributed.string
        #expect(string.utf16.count == line.utf16.count)
        #expect(!string.unicodeScalars.contains { $0.properties.isBidiControl })
        #expect(string.unicodeScalars.count(where: { $0 == "x" }) == Self.controls.count)
    }

    @Test
    func `each placeholder records the control it stands for`() throws {
        let rendered = try rendered(Self.overridden)
        let recorded = { (offset: Int) in
            rendered.attributed.attribute(.diffBidiControl, at: offset, effectiveRange: nil) as? String
        }

        #expect(recorded(3) == Self.rlo)
        #expect(recorded(7) == Self.pdf)
        #expect([0, 1, 2, 4, 5, 6, 8, 9, 10].allSatisfy { recorded($0) == nil })
    }

    @Test
    func `a placeholder is drawn apart from the text around it`() throws {
        let rendered = try rendered(Self.overridden)
        let background = { (offset: Int) in
            rendered.attributed.attribute(.backgroundColor, at: offset, effectiveRange: nil) as? NSColor
        }

        #expect(background(3) != nil)
        #expect(background(7) != nil)
        #expect(background(2) == nil)
        #expect(background(4) == nil)
    }

    @Test
    func `the placeholders stand for Unicode's bidi controls and nothing else`() {
        let scalars = (UInt32(0) ... 0x10FFFF).compactMap(Unicode.Scalar.init)

        let mismatched = scalars.filter { (BidiControls.placeholder(for: $0) != nil) != $0.properties.isBidiControl }

        #expect(mismatched.isEmpty)
    }

    @Test
    func `a character that shares a control's lead byte is revealed exactly when it is a control`() {
        // The UTF-8 of every control starts with the byte E2 or D8, which lead U+2000 to U+2FFF and U+0600 to U+063F:
        // each of those is looked for in the middle of a row and at its end.
        var placeholders = BidiControls.Placeholders()
        let led: [ClosedRange<UInt32>] = [0x0600 ... 0x063F, 0x2000 ... 0x2FFF]
        let scalars = led.joined().compactMap(Unicode.Scalar.init)

        let mismatched = scalars.filter { scalar in
            let rows = ["a\(String(scalar))b"[...], "a\(String(scalar))"[...]]
            return rows.contains { (placeholders.reveal($0, at: 0) != $0) != scalar.properties.isBidiControl }
        }

        #expect(mismatched.isEmpty)
    }

    @Test
    func `a row not stored as UTF-8 reveals its controls too`() throws {
        let bridged = NSString(string: Self.overridden) as String
        try #require(bridged.utf8.withContiguousStorageIfAvailable { _ in true } == nil)
        var placeholders = BidiControls.Placeholders()

        #expect(placeholders.reveal(bridged[...], at: 0) == "abc\u{25C2}def\u{25A1}ghi")
    }

    @Test
    func `each placeholder is one unit of the pane's own font, and no control itself`() throws {
        let font = DiffPalette.system.font as CTFont
        for control in Self.controls {
            let placeholder = try #require(BidiControls.placeholder(for: control))
            var units = Array(String(placeholder).utf16)
            var glyphs = [CGGlyph](repeating: 0, count: units.count)

            #expect(units.count == 1)
            #expect(String(control).utf16.count == 1)
            #expect(!placeholder.properties.isBidiControl)
            #expect(!placeholder.properties.isBidiMirrored)
            #expect(CTFontGetGlyphsForCharacters(font, &units, &glyphs, units.count))
        }
    }

    @Test
    func `the unified, old and new texts all show placeholders`() throws {
        let diff = DiffRenderer.render(
            oldText: "abc\(Self.rlo)def\(Self.pdf)ghi\n", newText: "abc\(Self.rlo)dXf\(Self.pdf)ghi\n",
            language: .plain)
        let sides = try [#require(diff.unified), #require(diff.old), #require(diff.new)]

        for side in sides {
            #expect(!side.attributed.string.unicodeScalars.contains { $0.properties.isBidiControl })
            #expect(side.attributed.string.unicodeScalars.contains("\u{25C2}"))
        }
    }

    @Test
    func `a file title's bidi controls show as placeholders`() throws {
        let file = FileDiffInput(
            title: "invoice\(Self.rlo)fdp.swift", oldText: "a\n", newText: "b\n", language: .plain)
        let rendered = try #require(DiffRenderer.renderCombined(files: [file], context: 1, expansions: [:]).unified)

        let titleRow = NSRange(location: 0, length: rendered.lineStarts[1] - 1)
        #expect((rendered.attributed.string as NSString).substring(with: titleRow) == "invoice\u{25C2}fdp.swift")
    }

    @Test
    func `a text without bidi controls renders as it did`() throws {
        // Latin, Hebrew, an arrow, CJK, an emoji family joined by ZWJs, dashes and a tab: none of them a bidi control.
        let lines = [
            "let caf\u{E9} = \"\u{5E9}\u{5DC}\u{5D5}\u{5DD}\" // \u{2192}",
            "\tlet \u{6F22}\u{5B57} = \"\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\" \u{2014} \u{2026}"
        ]
        let text = lines.joined(separator: "\n") + "\n"
        let rendered = try #require(DiffRenderer.render(oldText: text, newText: text, language: .swift).new)
        var keys = Set<NSAttributedString.Key>()
        let whole = NSRange(location: 0, length: rendered.attributed.length)
        rendered.attributed.enumerateAttributes(in: whole) { attributes, _, _ in keys.formUnion(attributes.keys) }

        #expect(rendered.attributed.string == lines.joined(separator: "\n"))
        #expect(keys.isSubset(of: [.font, .foregroundColor, .paragraphStyle]))
    }

    @Test
    func `a row without bidi controls is untouched by a control on another row`() throws {
        let plain = try rendered("let alpha = 1")
        let text = "let alpha = 1\n\(Self.overridden)\n"
        let mixed = try #require(DiffRenderer.render(oldText: text, newText: text, language: .plain).new)
        let first = NSRange(location: 0, length: 13)

        #expect(mixed.attributed.attributedSubstring(from: first) == plain.attributed.attributedSubstring(from: first))
    }

    // MARK: Layout

    @Test
    func `a right-to-left override lays out in logical order`() throws {
        let rendered = try rendered(Self.overridden)
        let textView = try paneTextView(showing: rendered)

        let carets = try caretOffsets(of: firstLine(in: #require(textView.textLayoutManager)))

        #expect(zip(carets, carets.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test
    func `each placeholder takes one column, like the character it stands in for`() throws {
        let rendered = try rendered(Self.overridden)
        let textView = try paneTextView(showing: rendered)
        let width = columnWidth(of: rendered)

        let carets = try caretOffsets(of: firstLine(in: #require(textView.textLayoutManager)))

        #expect(carets.enumerated().allSatisfy { abs($0.element - carets[0] - CGFloat($0.offset) * width) < 0.01 })
    }

    @Test
    func `a card pane's layout lays out the override in logical order`() throws {
        let layout = try StaticTextLayout(rendered: rendered(Self.overridden))
        layout.layOut(mode: .viewport, viewportWidth: 800)

        let carets = try caretOffsets(of: firstLine(in: layout.layoutManager))

        #expect(zip(carets, carets.dropFirst()).allSatisfy { $0 < $1 })
    }

    // MARK: Hover

    @Test
    func `a hover after a placeholder resolves the source's column`() throws {
        // "abc⟨RLO⟩def⟨PDF⟩ghi alpha": "alpha" takes columns 12 to 16.
        let rendered = try rendered(Self.overridden + " alpha")
        let textView = try paneTextView(showing: rendered)

        let hit = try #require(
            HoverHitTester.hit(at: point(column: 14, in: rendered), textView: textView, rendered: rendered))

        #expect(hit.utf16Column == 14)
        #expect((rendered.attributed.string as NSString).substring(with: hit.identifierRange) == "alpha")
    }

    @Test
    func `a hover inside an overridden run resolves the source's column`() throws {
        let rendered = try rendered(Self.overridden)
        let textView = try paneTextView(showing: rendered)

        let hit = try #require(
            HoverHitTester.hit(at: point(column: 4, in: rendered), textView: textView, rendered: rendered))

        #expect(hit.utf16Column == 4)
    }

    // MARK: Intraline emphasis

    @Test
    func `intraline emphasis on a line with a control lands on the changed character`() throws {
        // Only "d" changes, to "X", at column 4: the first character the override would reverse.
        let diff = DiffRenderer.render(
            oldText: "abc\(Self.rlo)def\(Self.pdf)ghi\n", newText: "abc\(Self.rlo)Xef\(Self.pdf)ghi\n",
            language: .plain, granularity: .character)
        let new = try #require(diff.new)
        var emphasis: [NSRange] = []
        let whole = NSRange(location: 0, length: new.attributed.length)
        new.attributed.enumerateAttribute(.diffEmphasis, in: whole) { value, range, _ in
            if value != nil { emphasis.append(range) }
        }
        try #require(emphasis == [NSRange(location: 4, length: 1)])
        let textView = try paneTextView(showing: new)
        let line = try firstLine(in: #require(textView.textLayoutManager))

        // The layout fragment fills an emphasis from the caret before its first unit to the caret after its last.
        let start = line.locationForCharacter(at: 4).x
        let end = line.locationForCharacter(at: 5).x
        let width = columnWidth(of: new)
        #expect(abs(end - start - width) < 0.01)
        #expect(abs(start - line.locationForCharacter(at: 0).x - 4 * width) < 0.01)
    }
}

import AppKit
import AtelierSwiftSyntax
import DiffCore
import DiffRendering
import Foundation
import Testing

@testable import DiffTextKit

/// When colours land, a card pane, whose layout manager keeps every row it laid out, colours all of them: TextKit asks
/// the validator for a row only when it lays the row out, so a kept row left out would show the lexer's colours when
/// it scrolls back in. A file pane lays out again whatever scrolls in, and colours its viewport alone. Lays a text out
/// on the main actor, without drawing it.
@MainActor
struct RefinedColorsLaidOutRowsTests {
    private static let rowCount = 200
    private static let text = Array(repeating: "let set = [1]", count: rowCount).joined(separator: "\n") + "\n"

    private static func sides() throws -> RefinedSides {
        let lines = DiffRenderer.tokensByLine(
            try SwiftSyntaxHighlights.tokens(in: text), text: text, lines: DiffModel.lines(of: text))
        var layered = LayeredLineTokens(lineCount: lines.count)
        layered.apply(
            TierUpdate(
                layer: .syntactic, coverage: .complete,
                revision: SourceRevision(documentID: "a.swift", language: .swift, key: .content("blob")),
                lines: 0 ..< lines.count, tokens: lines))
        return RefinedSides(old: layered, new: layered)
    }

    @Test(arguments: [true, false])
    func `landing colours every row laid out when the layout manager keeps them`(retainsLayout: Bool) throws {
        let rendered = try #require(DiffRenderer.render(oldText: Self.text, newText: Self.text, language: .swift).new)
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.frame = NSRect(x: 0, y: 0, width: 600, height: 100)
        textView.textStorage?.setAttributedString(rendered.attributed)
        let layoutManager = try #require(textView.textLayoutManager)
        let contentManager = try #require(layoutManager.textContentManager)
        // Every row laid out, as a card that was scrolled through keeps them.
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        let colors = RefinedColors()
        colors.install(on: layoutManager, retainsLayout: retainsLayout)

        colors.update(rendered: rendered, sides: try Self.sides(), view: textView)

        // `set` on the last row, far below the 100-point viewport.
        let offset = rendered.lineStarts[Self.rowCount - 1] + 4
        let location = try #require(contentManager.location(layoutManager.documentRange.location, offsetBy: offset))
        var color: NSColor?
        layoutManager.enumerateRenderingAttributes(from: layoutManager.documentRange.location, reverse: false) {
            _, attributes, range in
            if range.contains(location) { color = attributes[.foregroundColor] as? NSColor }
            return color == nil
        }
        #expect(color == (retainsLayout ? rendered.palette.textColor : nil))
    }
}

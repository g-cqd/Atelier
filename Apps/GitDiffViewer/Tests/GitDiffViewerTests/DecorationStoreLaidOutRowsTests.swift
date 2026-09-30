import AppKit
import AtelierSwiftSyntax
import DiffCore
import DiffRendering
import Foundation
import Testing

@testable import DiffTextKit

/// When colours land, a card pane, whose layout manager keeps every row it laid out, colours all of them: TextKit asks
/// the validator for a row only when it lays the row out, so a kept row left out would stay plain when it scrolls
/// back in. A file pane colours its viewport alone, and each other row it kept laid out once the row shows
/// (`DecorationStore.viewportDidLayout()`). Lays a text out on the main actor, without drawing it.
@MainActor
@Suite(.mainActorLane)
struct DecorationStoreLaidOutRowsTests {
    private static let rowCount = 200
    private static let text = Array(repeating: "let set = [1]", count: rowCount).joined(separator: "\n") + "\n"

    private static func decorations() throws -> DiffDecorations {
        let layers = DecorationFixtures.layers(try SwiftSyntaxHighlights.tokens(in: text), text: text)
        return DecorationFixtures.colors(old: layers, new: layers)
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
        let store = DecorationStore()
        store.install(on: layoutManager, retainsLayout: retainsLayout)

        store.update(rendered: rendered, decorations: try Self.decorations(), view: textView)

        // `let` on the last row, far below the 100-point viewport.
        let offset = rendered.lineStarts[Self.rowCount - 1]
        let location = try #require(contentManager.location(layoutManager.documentRange.location, offsetBy: offset))
        var color: NSColor?
        layoutManager.enumerateRenderingAttributes(from: layoutManager.documentRange.location, reverse: false) {
            _, attributes, range in
            if range.contains(location) { color = attributes[.foregroundColor] as? NSColor }
            return color == nil
        }
        #expect(color == (retainsLayout ? rendered.palette.color(for: .keyword) : nil))
    }
}

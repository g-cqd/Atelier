import AppKit
import AtelierSwiftSyntax
import DiffCore
import DiffRendering
import Foundation
import Metal
import SwiftUI
import Testing

@testable import DiffTextKit

/// What a pane shows as the stages after the text land over it (PERF-09 stages 1 and 2), read from the contents its
/// layer tree holds, as ``DiagnosticRedrawPixelsTests`` reads them.
///
/// The text is plain at first. The lexer's colour lands over it, then swift-syntax's over the lexer's: `set` in
/// `let set = [1]` is a keyword to the lexer and a declared name to swift-syntax, so the first row changes colour when
/// swift-syntax lands, and the second, whose every word both tiers colour alike, does not.
@MainActor
@Suite(
    .mainActorLane,
    .enabled(if: MTLCreateSystemDefaultDevice() != nil, "Core Animation's renderer draws into a Metal texture"))
struct DecorationStorePixelsTests {
    static let text = "let set = [1]\nlet other = 2\n"

    static func diff() -> RenderedDiff {
        DiffRenderer.render(oldText: text, newText: text, language: .swift)
    }

    /// The lexer's colour of both sides of ``text``.
    static func lexed() -> DiffDecorations {
        let layers = DecorationFixtures.layers(
            LexicalHighlightEngine().highlight(utf8: Array(text.utf8), language: .swift), text: text, layer: .lexical)
        return DecorationFixtures.colors(old: layers, new: layers, version: 1)
    }

    /// swift-syntax's colour over the lexer's, on both sides of ``text``.
    static func refined() throws -> DiffDecorations {
        let lexical = try #require(lexed().new.colors)
        let layers = DecorationFixtures.layers(try SwiftSyntaxHighlights.tokens(in: text), text: text, over: lexical)
        return DecorationFixtures.colors(old: layers, new: layers, version: 2)
    }

    @Test
    func `before anything lands, the pane draws what it draws without a validator`() throws {
        let rendered = try #require(Self.diff().new)
        let pane = try HostedDecoratedPane(rendered: rendered, decorations: nil)
        let pending = try pane.pixels()
        let layoutManager = try #require(pane.textView.textLayoutManager)
        var attributed = 0
        layoutManager.enumerateRenderingAttributes(from: layoutManager.documentRange.location, reverse: false) {
            _, _, _ in
            attributed += 1
            return true
        }

        layoutManager.renderingAttributesValidator = nil
        layoutManager.invalidateRenderingAttributes(for: layoutManager.documentRange)
        pane.settle()

        #expect(attributed == 0)
        #expect(try pane.pixels().differing(from: pending, in: pane.bounds) == 0)
    }

    @Test
    func `the lexer's colour lands over the plain text, and swift-syntax's over the lexer's`() throws {
        let rendered = try #require(Self.diff().new)
        let pane = try HostedDecoratedPane(rendered: rendered, decorations: nil)
        let plain = try pane.pixels()
        let keyword = rendered.palette.color(for: .keyword)

        pane.update(decorations: Self.lexed())
        let lexed = try pane.pixels()
        #expect(try pane.renderingColor(at: 4) == keyword)
        #expect(lexed.differing(from: plain, in: try pane.textBand(ofRow: 0)) > 0)
        #expect(lexed.differing(from: plain, in: try pane.textBand(ofRow: 1)) > 0)

        pane.update(decorations: try Self.refined())
        let refined = try pane.pixels()
        // `set` turns plain, the storage's own colour, so it needs no rendering attribute; `let` stays a keyword.
        #expect(try pane.renderingColor(at: 4) == nil)
        #expect(try pane.renderingColor(at: 0) == keyword)
        #expect(refined.differing(from: lexed, in: try pane.textBand(ofRow: 0)) > 0)
        #expect(refined.differing(from: lexed, in: try pane.textBand(ofRow: 1)) == 0)
        let fresh = try HostedDecoratedPane(rendered: rendered, decorations: try Self.refined()).pixels()
        #expect(refined.differing(from: fresh, in: pane.bounds) == 0)
    }

    @Test
    func `colour, emphasis and a moved row land with no fragment laid out again`() throws {
        let diff = DiffRenderer.render(
            oldText: "let a = 1\nlet b = 2\n", newText: "let a = 1\nlet b = 3\n", language: .swift)
        let rendered = try #require(diff.new)
        let pane = try HostedDecoratedPane(rendered: rendered, decorations: nil)
        let layoutManager = try #require(pane.textView.textLayoutManager)
        func fragments() -> [NSTextLayoutFragment] {
            var all: [NSTextLayoutFragment] = []
            _ = layoutManager.enumerateTextLayoutFragments(from: layoutManager.documentRange.location) { fragment in
                all.append(fragment)
                return true
            }
            return all
        }
        let before = fragments()
        let lines = before.map(\.textLineFragments)
        try #require(before.count >= 2)
        let plain = try pane.pixels()

        var decorations = Self.lexed()
        pane.update(decorations: decorations)
        decorations.new.emphasis = [1: [8 ..< 9]]
        decorations.moved = MovedLines(old: [false, true], new: [false, true])
        decorations.markVersion = 1
        pane.update(decorations: decorations)

        let after = fragments()
        let sameFragments = after.elementsEqual(before, by: ===)
        #expect(sameFragments)
        #expect(zip(before, lines).allSatisfy { $0.textLineFragments.elementsEqual($1, by: ===) })
        #expect(try pane.pixels().differing(from: plain, in: try pane.textBand(ofRow: 1)) > 0)
        let row = try #require(after.compactMap { $0 as? DiffLayoutFragment }.first { $0.row?.kind == .added })
        #expect(row.backgroundColor == rendered.palette.rowBackground(for: .added, side: .new, isMoved: true))
    }

    @Test
    func `taking the decorations away draws the plain first paint again`() throws {
        let pane = try HostedDecoratedPane(rendered: try #require(Self.diff().new), decorations: nil)
        let before = try pane.pixels()
        pane.update(decorations: try Self.refined())

        pane.update(decorations: nil)

        #expect(try pane.pixels().differing(from: before, in: pane.bounds) == 0)
    }

    @Test
    func `a card pane draws the decorations when they land`() throws {
        let diff = Self.diff()
        let pane = try HostedDecoratedCard(diff: diff, decorations: nil)
        let before = try pane.pixels()

        pane.update(decorations: try Self.refined())

        let after = try pane.pixels()
        #expect(after.differing(from: before, in: pane.bounds) > 0)
        let fresh = try HostedDecoratedCard(diff: diff, decorations: try Self.refined()).pixels()
        #expect(after.differing(from: fresh, in: pane.bounds) == 0)
    }
}

/// A ``DiffTextView`` with decorations, hosted as the app hosts it in a borderless window that is never ordered in.
@MainActor
final class HostedDecoratedPane {
    let window: NSWindow
    private let host: NSHostingView<DiffTextView>
    private let rendered: RenderedText

    init(rendered: RenderedText, decorations: DiffDecorations?) throws {
        self.rendered = rendered
        host = NSHostingView(rootView: DiffTextView(rendered: rendered, gutter: .new).decorated(with: decorations))
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.borderless], backing: .buffered,
            defer: false)
        window.contentView = host
        settle()
        try #require(host.layer != nil)
    }

    var bounds: NSRect { host.bounds }

    var textView: NSTextView {
        get throws { try #require(firstSubview(NSTextView.self, in: host)) }
    }

    /// Hands the pane new decorations as SwiftUI does, then lets the change reach the screen.
    func update(decorations: DiffDecorations?) {
        host.rootView = DiffTextView(rendered: rendered, gutter: .new).decorated(with: decorations)
        settle()
    }

    func settle() {
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0, true)
    }

    /// The colour the rendering attributes give the unit at `offset`, nil where they give none.
    func renderingColor(at offset: Int) throws -> NSColor? {
        let layoutManager = try #require(try textView.textLayoutManager)
        let contentManager = try #require(layoutManager.textContentManager)
        let location = try #require(contentManager.location(layoutManager.documentRange.location, offsetBy: offset))
        var color: NSColor?
        layoutManager.enumerateRenderingAttributes(from: layoutManager.documentRange.location, reverse: false) {
            _, attributes, range in
            if range.contains(location) { color = attributes[.foregroundColor] as? NSColor }
            return color == nil
        }
        return color
    }

    /// Where `row`'s text lies in the window, right of the gutter.
    func textBand(ofRow row: Int) throws -> NSRect {
        let textView = try textView
        let layoutManager = try #require(textView.textLayoutManager)
        let contentManager = try #require(layoutManager.textContentManager)
        let location = try #require(
            contentManager.location(layoutManager.documentRange.location, offsetBy: rendered.lineStarts[row]))
        let fragment = try #require(layoutManager.textLayoutFragment(for: location))
        var frame = fragment.layoutFragmentFrame
        frame.origin.y += textView.textContainerOrigin.y
        let rowInWindow = textView.convert(frame, to: nil)
        let textStart = textView.convert(textView.bounds, to: nil).minX
        return NSRect(x: textStart, y: rowInWindow.minY, width: bounds.width - textStart, height: rowInWindow.height)
    }

    func pixels() throws -> LayerPixels {
        try LayerPixels.composite(try #require(host.layer))
    }
}

/// An ``EmbeddedDiffTextView`` with decorations, hosted as a card's body hosts it.
@MainActor
final class HostedDecoratedCard {
    private static let width: CGFloat = 600
    let window: NSWindow
    private let host: NSHostingView<EmbeddedDiffTextView>
    private let layouts: CardLayouts

    init(diff: RenderedDiff, decorations: DiffDecorations?) throws {
        layouts = CardLayouts(rendered: diff)
        host = NSHostingView(rootView: Self.pane(layouts, decorations: decorations))
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 400), styleMask: [.borderless],
            backing: .buffered, defer: false)
        window.contentView = host
        settle()
        try #require(host.layer != nil)
    }

    private static func pane(_ layouts: CardLayouts, decorations: DiffDecorations?) -> EmbeddedDiffTextView {
        EmbeddedDiffTextView(layouts: layouts, side: .new, gutter: .new, width: width, wrapMode: .none)
            .decorated(with: decorations)
    }

    var bounds: NSRect { host.bounds }

    func update(decorations: DiffDecorations?) {
        host.rootView = Self.pane(layouts, decorations: decorations)
        settle()
    }

    func settle() {
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0, true)
    }

    func pixels() throws -> LayerPixels {
        try LayerPixels.composite(try #require(host.layer))
    }
}

/// The first view of `type` in `view`'s tree, depth first.
@MainActor
func firstSubview<View: NSView>(_ type: View.Type, in view: NSView) -> View? {
    if let match = view as? View { return match }
    return view.subviews.lazy.compactMap { firstSubview(type, in: $0) }.first
}

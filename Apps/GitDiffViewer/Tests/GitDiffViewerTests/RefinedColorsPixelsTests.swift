import AppKit
import AtelierSwiftSyntax
import DiffCore
import DiffRendering
import Foundation
import Metal
import SwiftUI
import Testing

@testable import DiffTextKit

/// What a pane shows as swift-syntax's colour lands over the lexer's (PERF-11 step 1), read from the contents its layer
/// tree holds, as ``DiagnosticRedrawPixelsTests`` reads them.
///
/// `set` in `let set = [1]` is a keyword to the lexer and a declared name to swift-syntax, so the first row changes
/// colour when the tier lands, and the second, whose every word both tiers colour alike, does not.
@MainActor
@Suite(.enabled(if: MTLCreateSystemDefaultDevice() != nil, "Core Animation's renderer draws into a Metal texture"))
struct RefinedColorsPixelsTests {
    static let text = "let set = [1]\nlet other = 2\n"

    static func diff() -> RenderedDiff {
        DiffRenderer.render(oldText: text, newText: text, language: .swift)
    }

    /// swift-syntax's tokens for both sides of ``text``, as one update of its layer.
    static func sides() throws -> RefinedSides {
        let tokens = try SwiftSyntaxHighlights.tokens(in: text)
        let lines = DiffRenderer.tokensByLine(tokens, text: text, lines: DiffModel.lines(of: text))
        var layered = LayeredLineTokens(lineCount: lines.count)
        layered.apply(
            TierUpdate(
                layer: .syntactic, coverage: .complete,
                revision: SourceRevision(documentID: "a.swift", language: .swift, key: .content("blob")),
                lines: 0 ..< lines.count, tokens: lines))
        return RefinedSides(old: layered, new: layered)
    }

    @Test
    func `before the tier lands, the pane draws what it draws without a validator`() throws {
        let rendered = try #require(Self.diff().new)
        let pane = try HostedRefinedPane(rendered: rendered, sides: nil)
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
    func `a keyword to the lexer turns plain once swift-syntax lands`() throws {
        let rendered = try #require(Self.diff().new)
        let pane = try HostedRefinedPane(rendered: rendered, sides: nil)
        let before = try pane.pixels()
        let keyword = rendered.palette.color(for: .keyword)
        let storageColor = rendered.attributed.attribute(.foregroundColor, at: 4, effectiveRange: nil) as? NSColor
        #expect(storageColor == keyword)

        pane.update(sides: try Self.sides())

        let after = try pane.pixels()
        #expect(try pane.renderingColor(at: 4) == rendered.palette.textColor)
        // `let` keeps the storage's keyword colour, so it needs no rendering attribute.
        #expect(try pane.renderingColor(at: 0) == nil)
        #expect(after.differing(from: before, in: try pane.textBand(ofRow: 0)) > 0)
        #expect(after.differing(from: before, in: try pane.textBand(ofRow: 1)) == 0)
        let fresh = try HostedRefinedPane(rendered: rendered, sides: try Self.sides()).pixels()
        #expect(after.differing(from: fresh, in: pane.bounds) == 0)
    }

    @Test
    func `the tier's landing lays no fragment out again`() throws {
        let pane = try HostedRefinedPane(rendered: try #require(Self.diff().new), sides: nil)
        let layoutManager = try #require(pane.textView.textLayoutManager)
        var fragments: [NSTextLayoutFragment] = []
        _ = layoutManager.enumerateTextLayoutFragments(from: layoutManager.documentRange.location) { fragment in
            fragments.append(fragment)
            return true
        }
        let lines = fragments.map(\.textLineFragments)
        try #require(fragments.count >= 2)

        pane.update(sides: try Self.sides())

        var after: [NSTextLayoutFragment] = []
        _ = layoutManager.enumerateTextLayoutFragments(from: layoutManager.documentRange.location) { fragment in
            after.append(fragment)
            return true
        }
        let sameFragments = after.elementsEqual(fragments, by: ===)
        #expect(sameFragments)
        #expect(zip(fragments, lines).allSatisfy { $0.textLineFragments.elementsEqual($1, by: ===) })
    }

    @Test
    func `taking the refined colour away draws the first paint again`() throws {
        let pane = try HostedRefinedPane(rendered: try #require(Self.diff().new), sides: nil)
        let before = try pane.pixels()
        pane.update(sides: try Self.sides())

        pane.update(sides: nil)

        #expect(try pane.pixels().differing(from: before, in: pane.bounds) == 0)
    }

    @Test
    func `a card pane draws the refined colour when it lands`() throws {
        let diff = Self.diff()
        let pane = try HostedRefinedCard(diff: diff, sides: nil)
        let before = try pane.pixels()

        pane.update(sides: try Self.sides())

        let after = try pane.pixels()
        #expect(after.differing(from: before, in: pane.bounds) > 0)
        let fresh = try HostedRefinedCard(diff: diff, sides: try Self.sides()).pixels()
        #expect(after.differing(from: fresh, in: pane.bounds) == 0)
    }
}

/// A ``DiffTextView`` with refined colours, hosted as the app hosts it in a borderless window that is never ordered in.
@MainActor
final class HostedRefinedPane {
    let window: NSWindow
    private let host: NSHostingView<DiffTextView>
    private let rendered: RenderedText

    init(rendered: RenderedText, sides: RefinedSides?) throws {
        self.rendered = rendered
        host = NSHostingView(rootView: DiffTextView(rendered: rendered, gutter: .new).refined(with: sides))
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

    /// Hands the pane new refined sides as SwiftUI does, then lets the change reach the screen.
    func update(sides: RefinedSides?) {
        host.rootView = DiffTextView(rendered: rendered, gutter: .new).refined(with: sides)
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

/// An ``EmbeddedDiffTextView`` with refined colours, hosted as a card's body hosts it.
@MainActor
final class HostedRefinedCard {
    private static let width: CGFloat = 600
    let window: NSWindow
    private let host: NSHostingView<EmbeddedDiffTextView>
    private let layouts: CardLayouts

    init(diff: RenderedDiff, sides: RefinedSides?) throws {
        layouts = CardLayouts(rendered: diff)
        host = NSHostingView(rootView: Self.pane(layouts, sides: sides))
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 400), styleMask: [.borderless],
            backing: .buffered, defer: false)
        window.contentView = host
        settle()
        try #require(host.layer != nil)
    }

    private static func pane(_ layouts: CardLayouts, sides: RefinedSides?) -> EmbeddedDiffTextView {
        EmbeddedDiffTextView(layouts: layouts, side: .new, gutter: .new, width: width, wrapMode: .none)
            .refined(with: sides)
    }

    var bounds: NSRect { host.bounds }

    func update(sides: RefinedSides?) {
        host.rootView = Self.pane(layouts, sides: sides)
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

import AppKit
import DiffCore
import SwiftUI
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// A card pane stops at its edges, as it does by default: it never rubber-bands past them, sideways or down and up,
/// unless bouncing at the edges is turned on (book SET-09).
@MainActor
struct CardPaneElasticityTests {
    @Test(arguments: [false, true])
    func `a card pane never rubber-bands, whether its lines fit or run past it`(overflowing: Bool) throws {
        let tail = overflowing ? String(repeating: "long ", count: 200) : ""
        let text = (1 ... 40).map { "let value\($0) = \($0) \(tail)" }.joined(separator: "\n") + "\n"
        let layouts = CardLayouts(rendered: DiffRenderer.render(oldText: text, newText: text, language: .plain))
        let host = NSHostingView(rootView: Self.pane(layouts, width: 600))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 300), styleMask: [.borderless], backing: .buffered,
            defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let textView = try #require(Self.first(NSTextView.self, in: host))
        let scrollView = try #require(textView.enclosingScrollView)
        let runsPast = textView.frame.width > scrollView.contentView.bounds.width
        #expect(runsPast == overflowing)

        // A new width sizes the text view again, which is when sideways elasticity used to be reconsidered.
        host.rootView = Self.pane(layouts, width: 500)
        window.setContentSize(NSSize(width: 500, height: 300))
        host.layoutSubtreeIfNeeded()

        #expect(scrollView.verticalScrollElasticity == .none)
        #expect(scrollView.horizontalScrollElasticity == .none)
    }

    /// Bouncing turned on, then off again, reaches a card that is already open (book SET-09). A card's pane scrolls
    /// sideways only: down and up, the card list scrolls, and bounces, for it.
    @Test
    func `a card pane rubber-bands sideways while bouncing is on`() throws {
        let text = (1 ... 40).map { "let value\($0) = \($0)" }.joined(separator: "\n") + "\n"
        let layouts = CardLayouts(rendered: DiffRenderer.render(oldText: text, newText: text, language: .plain))
        let host = NSHostingView(rootView: Self.pane(layouts, width: 600))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 300), styleMask: [.borderless], backing: .buffered,
            defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let scrollView = try #require(Self.first(NSTextView.self, in: host)?.enclosingScrollView)

        host.rootView = Self.pane(layouts, width: 600, bouncesAtEdges: true)
        host.layoutSubtreeIfNeeded()
        #expect(scrollView.horizontalScrollElasticity == .automatic)
        #expect(scrollView.verticalScrollElasticity == .none)

        host.rootView = Self.pane(layouts, width: 600)
        host.layoutSubtreeIfNeeded()
        #expect(scrollView.horizontalScrollElasticity == .none)
        #expect(scrollView.verticalScrollElasticity == .none)
    }

    private static func pane(_ layouts: CardLayouts, width: CGFloat, bouncesAtEdges: Bool = false)
        -> EmbeddedDiffTextView
    {
        EmbeddedDiffTextView(
            layouts: layouts, side: .unified, gutter: .dual, width: width, wrapMode: .none,
            bouncesAtEdges: bouncesAtEdges)
    }

    private static func first<View: NSView>(_ type: View.Type, in view: NSView) -> View? {
        if let match = view as? View { return match }
        return view.subviews.lazy.compactMap { first(type, in: $0) }.first
    }
}

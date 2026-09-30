import AppKit
import DiffCore
import SwiftUI
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// A file pane searches its text through the text view's own find bar (text-renderer.md §1.3, finding 6; §5, M0
/// item 12).
@MainActor
@Suite(.mainActorLane)
struct FilePaneFindBarTests {
    @Test
    func `find shows the bar over the pane`() throws {
        let text = (1 ... 80).map { "let value\($0) = \($0)" }.joined(separator: "\n") + "\n"
        let rendered = try #require(DiffRenderer.render(oldText: text, newText: text, language: .plain).unified)
        let host = NSHostingView(rootView: DiffTextView(rendered: rendered, gutter: .dual, wrapsLines: false))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 300), styleMask: [.borderless], backing: .buffered,
            defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let scrollView = try #require(Self.first(NSScrollView.self, in: host))
        let textView = try #require(scrollView.documentView as? NSTextView)
        #expect(textView.usesFindBar)
        #expect(textView.isIncrementalSearchingEnabled)

        textView.performTextFinderAction(Self.item(.showFindInterface))
        #expect(scrollView.isFindBarVisible)
    }

    private static func item(_ action: NSTextFinder.Action) -> NSMenuItem {
        let item = NSMenuItem()
        item.tag = action.rawValue
        return item
    }

    private static func first<View: NSView>(_ type: View.Type, in view: NSView) -> View? {
        if let match = view as? View { return match }
        return view.subviews.lazy.compactMap { first(type, in: $0) }.first
    }
}

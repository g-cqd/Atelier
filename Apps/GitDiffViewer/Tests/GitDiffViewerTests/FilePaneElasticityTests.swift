import AppKit
import DiffCore
import SwiftUI
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// A file pane stops at its edges, as it does by default: it never rubber-bands past them, down, up or sideways,
/// unless bouncing at the edges is turned on (book SET-09).
@MainActor
@Suite(.mainActorLane)
struct FilePaneElasticityTests {
    @Test(arguments: [false, true])
    func `a file pane never rubber-bands, whether its lines fit or run past it`(overflowing: Bool) throws {
        let tail = overflowing ? String(repeating: "long ", count: 200) : ""
        let text = (1 ... 80).map { "let value\($0) = \($0) \(tail)" }.joined(separator: "\n") + "\n"
        let rendered = try #require(DiffRenderer.render(oldText: text, newText: text, language: .plain).unified)
        let host = NSHostingView(rootView: DiffTextView(rendered: rendered, gutter: .dual, wrapsLines: false))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 300), styleMask: [.borderless], backing: .buffered,
            defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let scrollView = try #require(Self.first(NSScrollView.self, in: host))
        let runsPast = (scrollView.documentView?.frame.width ?? 0) > scrollView.contentView.bounds.width
        #expect(runsPast == overflowing)

        // A resize lays the pane out again, which is when sideways scrolling used to be reconsidered.
        window.setContentSize(NSSize(width: 500, height: 280))
        host.layoutSubtreeIfNeeded()

        #expect(scrollView.verticalScrollElasticity == .none)
        #expect(scrollView.horizontalScrollElasticity == .none)
    }

    /// Bouncing turned on, then off again, reaches a pane that is already open (book SET-09).
    @Test
    func `a file pane rubber-bands at its edges while bouncing is on`() throws {
        let text = (1 ... 80).map { "let value\($0) = \($0)" }.joined(separator: "\n") + "\n"
        let rendered = try #require(DiffRenderer.render(oldText: text, newText: text, language: .plain).unified)
        let host = NSHostingView(rootView: DiffTextView(rendered: rendered, gutter: .dual, bouncesAtEdges: false))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 300), styleMask: [.borderless], backing: .buffered,
            defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let scrollView = try #require(Self.first(NSScrollView.self, in: host))

        host.rootView = DiffTextView(rendered: rendered, gutter: .dual, bouncesAtEdges: true)
        host.layoutSubtreeIfNeeded()
        #expect(scrollView.verticalScrollElasticity == .automatic)
        #expect(scrollView.horizontalScrollElasticity == .automatic)

        host.rootView = DiffTextView(rendered: rendered, gutter: .dual, bouncesAtEdges: false)
        host.layoutSubtreeIfNeeded()
        #expect(scrollView.verticalScrollElasticity == .none)
        #expect(scrollView.horizontalScrollElasticity == .none)
    }

    private static func first<View: NSView>(_ type: View.Type, in view: NSView) -> View? {
        if let match = view as? View { return match }
        return view.subviews.lazy.compactMap { first(type, in: $0) }.first
    }
}

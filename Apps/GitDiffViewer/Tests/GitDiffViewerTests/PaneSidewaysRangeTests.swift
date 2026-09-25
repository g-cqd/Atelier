import AppKit
import DiffCore
import SwiftUI
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// A pane whose lines fit has nothing to scroll sideways, freshly built and after a re-render: its text is no wider
/// than what shows of it, and shows from its leading edge.
@MainActor
@Suite(.mainActorLane)
struct PaneSidewaysRangeTests {
    private static let text = (1 ... 30).map { "let value\($0) = \($0)" }.joined(separator: "\n") + "\n"

    private static func diff() -> RenderedDiff {
        DiffRenderer.render(oldText: text, newText: text, language: .plain)
    }

    @Test(arguments: [WrapMode.none, .viewport])
    func `a card pane whose lines fit has no sideways range, built and re-rendered`(mode: WrapMode) throws {
        let sut = Hosted(Self.card(mode: mode))
        try sut.expectNoSidewaysRange("fresh")

        sut.host.rootView = Self.card(mode: mode)
        sut.settle()

        try sut.expectNoSidewaysRange("re-rendered")
    }

    @Test(arguments: [false, true])
    func `a file pane whose lines fit has no sideways range, built and re-rendered`(wrapsLines: Bool) throws {
        let sut = Hosted(try Self.file(wrapsLines: wrapsLines))
        try sut.expectNoSidewaysRange("fresh")

        sut.host.rootView = try Self.file(wrapsLines: wrapsLines)
        sut.settle()

        try sut.expectNoSidewaysRange("re-rendered")
    }

    private static func card(mode: WrapMode) -> EmbeddedDiffTextView {
        EmbeddedDiffTextView(
            layouts: CardLayouts(rendered: diff()), side: .unified, gutter: .dual, width: 600, wrapMode: mode)
    }

    private static func file(wrapsLines: Bool) throws -> DiffTextView {
        DiffTextView(rendered: try #require(diff().unified), gutter: .dual, wrapsLines: wrapsLines)
    }
}

/// A pane hosted as the app hosts it, in a borderless window that is never ordered in.
@MainActor
private final class Hosted<Pane: View> {
    let host: NSHostingView<Pane>
    private let window: NSWindow

    init(_ pane: Pane) {
        host = NSHostingView(rootView: pane)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 300), styleMask: [.borderless], backing: .buffered,
            defer: false)
        window.contentView = host
        settle()
    }

    /// Lays out and displays what needs it, and lets the run loop turn once, as it does between two events.
    func settle() {
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0, true)
        host.layoutSubtreeIfNeeded()
    }

    func expectNoSidewaysRange(_ moment: Comment) throws {
        let textView = try #require(Self.first(NSTextView.self, in: host))
        let clip = try #require(textView.enclosingScrollView?.contentView)
        #expect(textView.frame.width <= clip.bounds.width, moment)
        #expect(clip.bounds.minX == 0, moment)
    }

    private static func first<View: NSView>(_ type: View.Type, in view: NSView) -> View? {
        if let match = view as? View { return match }
        return view.subviews.lazy.compactMap { first(type, in: $0) }.first
    }
}

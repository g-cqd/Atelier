import AppKit
import DiffCore
import SwiftUI
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// A file tab keeps its panes' scroll position while the file list shows in its place, and gets it back when it
/// shows again, rendered anew (book TAB-10).
@MainActor
struct FileTabScrollRestoreTests {
    private static func text(_ count: Int = 300) throws -> RenderedText {
        let lines = (1 ... count).map { "let value\($0) = \($0)" }.joined(separator: "\n") + "\n"
        return try #require(DiffRenderer.render(oldText: lines, newText: lines, language: .plain).unified)
    }

    private func makeMemory(retaining paths: Set<String> = ["a.swift"]) -> PaneScrollMemory {
        let memory = PaneScrollMemory()
        memory.retain(paths: paths)
        return memory
    }

    @Test(arguments: [false, true])
    func `a file pane shown again after the list comes back at the row it was scrolled to`(wrapsLines: Bool) throws {
        let memory = makeMemory()
        let sut = HostedTabPane(memory: memory)
        sut.show(try Self.text(), path: "a.swift", wrapsLines: wrapsLines)
        sut.scroll(to: 2_005)
        let before = try #require(sut.top())
        #expect(before.row > 0)

        sut.showList()
        sut.show(try Self.text(), path: "a.swift", wrapsLines: wrapsLines)

        let after = try #require(sut.top())
        #expect(after.row == before.row)
        #expect(abs(after.offset - before.offset) < 1)
    }

    @Test
    func `a file pane showing another file moves to it at its top, and the first file keeps its row`() throws {
        let memory = makeMemory(retaining: ["a.swift", "b.swift"])
        let sut = HostedTabPane(memory: memory)
        sut.show(try Self.text(), path: "a.swift")
        sut.scroll(to: 2_000)
        let before = try #require(sut.top())

        sut.show(try Self.text(), path: "b.swift")
        #expect(sut.scrollOffset == 0)

        sut.show(try Self.text(), path: "a.swift")
        #expect(sut.top()?.row == before.row)
    }

    @Test
    func `a file whose tab closed shows from its top again`() throws {
        let memory = makeMemory()
        let sut = HostedTabPane(memory: memory)
        sut.show(try Self.text(), path: "a.swift")
        sut.scroll(to: 2_000)

        sut.showList()
        memory.retain(paths: [])
        sut.show(try Self.text(), path: "a.swift")

        #expect(sut.scrollOffset == 0)
    }
}

/// A ``DiffTextView`` in the place the detail area gives it, or nothing there while the list shows, hosted in a
/// borderless window that is never ordered in.
@MainActor
private final class HostedTabPane {
    private let window: NSWindow
    private let host: NSHostingView<Slot>
    private let memory: PaneScrollMemory

    /// The file pane, or nothing, as the detail area swaps a file for the card list.
    struct Slot: View {
        var pane: DiffTextView?

        var body: some View {
            if let pane { pane } else { Color.clear }
        }
    }

    init(memory: PaneScrollMemory) {
        self.memory = memory
        host = NSHostingView(rootView: Slot())
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 300), styleMask: [.borderless], backing: .buffered,
            defer: false)
        window.contentView = host
        settle()
    }

    private var textView: NSTextView? { Self.first(NSTextView.self, in: host) }
    private var clipView: NSClipView? { textView?.enclosingScrollView?.contentView }

    var scrollOffset: CGFloat { clipView?.bounds.minY ?? -1 }

    /// Shows a new render of the file at `path`, as opening its tab does.
    func show(_ rendered: RenderedText, path: String, wrapsLines: Bool = false) {
        host.rootView = Slot(
            pane: DiffTextView(
                rendered: rendered, gutter: .dual, wrapsLines: wrapsLines, scrollMemory: memory,
                scrollMemoryPath: path))
        settle()
    }

    /// Takes the pane off screen, as showing the list does.
    func showList() {
        host.rootView = Slot()
        settle()
    }

    func scroll(to y: CGFloat) {
        guard let clipView else { return }
        clipView.scroll(to: NSPoint(x: clipView.bounds.minX, y: y))
        clipView.enclosingScrollView?.reflectScrolledClipView(clipView)
        settle()
    }

    /// The row whose line shows at the top of the pane, and how far into that line the pane is scrolled.
    func top() -> (row: Int, offset: CGFloat)? {
        guard let textView, let layoutManager = textView.textLayoutManager,
            let content = layoutManager.textContentManager,
            let rendered = Self.first(DiffGutterView.self, in: host)?.rendered,
            let fragment = layoutManager.textLayoutFragment(
                for: CGPoint(x: 0, y: textView.visibleRect.minY - textView.textContainerOrigin.y))
        else { return nil }
        let start = layoutManager.documentRange.location
        let row = rendered.rowIndex(containing: content.offset(from: start, to: fragment.rangeInElement.location))
        let offset = textView.visibleRect.minY - textView.textContainerOrigin.y - fragment.layoutFragmentFrame.minY
        return (row, offset)
    }

    /// Lays out and displays what needs it, and lets the run loop turn once, as it does between two events.
    private func settle() {
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0, true)
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
    }

    private static func first<View: NSView>(_ type: View.Type, in view: NSView) -> View? {
        if let match = view as? View { return match }
        return view.subviews.lazy.compactMap { first(type, in: $0) }.first
    }
}

import AppKit
import DiffCore
import SwiftUI
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// A file tab keeps its panes' scroll position while the file list shows in its place, and gets it back when it
/// shows again, rendered anew (book TAB-10).
@MainActor
@Suite(.mainActorLane)
struct FileTabScrollRestoreTests {
    private static func text(_ count: Int = 300) throws -> RenderedText {
        let lines = (1 ... count).map { "let value\($0) = \($0)" }.joined(separator: "\n") + "\n"
        return try #require(DiffRenderer.render(oldText: lines, newText: lines, language: .plain).unified)
    }

    /// `count` lines, every seventh wide enough to wrap in the pane, and to wrap onto more lines as it narrows.
    private static func wrappingText(_ count: Int = 300) throws -> RenderedText {
        let tail = String(repeating: "long ", count: 40)
        let lines =
            (1 ... count).map { $0.isMultiple(of: 7) ? "let value\($0) = \(tail)" : "let value\($0) = \($0)" }
            .joined(separator: "\n") + "\n"
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

    /// Far down a long file, the row comes back placed after TextKit's estimates of the rows above it, which are not
    /// laid out for it (`FilePaneScrollToRowTests`).
    @Test(arguments: [false, true])
    func `a long file's pane shown again comes back at the row it was scrolled to far down`(wrapsLines: Bool) throws {
        let memory = makeMemory()
        let sut = HostedTabPane(memory: memory)
        let text = try Self.text(3_000)
        sut.show(text, path: "a.swift", wrapsLines: wrapsLines)
        sut.scroll(to: 40_005)
        let before = try #require(sut.top())
        #expect(text.lineStarts[before.row] > RowPlacement.textLaidOutAbove)

        sut.showList()
        sut.show(try Self.text(3_000), path: "a.swift", wrapsLines: wrapsLines)

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

    /// A file that fits its pane opens at its top, whole (book DIFF-08), unless it comes back to a position: in a pane
    /// that scrolls past its end, a file that fits still scrolls.
    @Test
    func `a file that fits its pane comes back where it was scrolled, not to its top`() throws {
        let memory = makeMemory()
        let sut = HostedTabPane(memory: memory)
        sut.show(try Self.text(12), path: "a.swift", scrollsPastEnd: true)
        sut.scroll(to: 60)
        let before = try #require(sut.top())
        #expect(sut.scrollOffset == 60)

        sut.showList()
        sut.show(try Self.text(12), path: "a.swift", scrollsPastEnd: true)

        #expect(abs(sut.scrollOffset - 60) < 1)
        #expect(sut.top()?.row == before.row)
    }

    /// A pane made while the detail area has no size yet comes back to its position once it has one.
    @Test
    func `a file pane made before it has a size comes back where it was once it has one`() throws {
        let memory = makeMemory()
        let sut = HostedTabPane(memory: memory)
        sut.show(try Self.text(), path: "a.swift")
        sut.scroll(to: 2_005)
        let before = try #require(sut.top())

        sut.showList()
        sut.show(try Self.text(), path: "a.swift", height: 0)
        sut.resize(height: 300)

        let after = try #require(sut.top())
        #expect(after.row == before.row)
        #expect(abs(after.offset - before.offset) < 1)
    }

    /// A narrower pane wraps the lines anew, and TextKit lays out what shows from estimates of the rows above it: the
    /// row the pane came back to stays at its top, as long as nothing scrolled the pane since.
    @Test
    func `a file pane that came back to its row keeps it at its top as the pane narrows`() throws {
        let memory = makeMemory()
        let sut = HostedTabPane(memory: memory)
        sut.show(try Self.wrappingText(), path: "a.swift", wrapsLines: true)
        sut.scroll(to: 4_005)
        let before = try #require(sut.top())

        sut.showList()
        sut.show(try Self.wrappingText(), path: "a.swift", wrapsLines: true)
        sut.resize(width: 420, height: 300)

        let after = try #require(sut.top())
        #expect(after.row == before.row)
        #expect(abs(after.offset - before.offset) < 1)
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
        var width: CGFloat?
        var height: CGFloat = 300

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                if let pane { pane.frame(width: width, height: height) } else { Color.clear }
                Spacer(minLength: 0)
            }
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

    /// Shows a new render of the file at `path`, as opening its tab does, in a detail area `height` points tall.
    func show(
        _ rendered: RenderedText, path: String, wrapsLines: Bool = false, scrollsPastEnd: Bool = false,
        height: CGFloat = 300
    ) {
        host.rootView = Slot(
            pane: DiffTextView(
                rendered: rendered, gutter: .dual, wrapsLines: wrapsLines, scrollMemory: memory,
                scrollMemoryPath: path, scrollsPastEnd: scrollsPastEnd),
            height: height)
        settle()
    }

    /// Gives the detail area a new size, as the split view does once it lays the window out.
    func resize(width: CGFloat? = nil, height: CGFloat) {
        host.rootView.width = width
        host.rootView.height = height
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

    /// Lays out and displays what needs it, and lets the run loop turn once, as it does between two events; then
    /// lays out again as long as the text view asks for it, as the display cycles that follow do: a row the pane
    /// places is checked in the pass after it.
    private func settle() {
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0, true)
        for _ in 0 ..< 4 {
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            guard textView?.needsLayout == true else { break }
        }
    }

    private static func first<View: NSView>(_ type: View.Type, in view: NSView) -> View? {
        if let match = view as? View { return match }
        return view.subviews.lazy.compactMap { first(type, in: $0) }.first
    }
}

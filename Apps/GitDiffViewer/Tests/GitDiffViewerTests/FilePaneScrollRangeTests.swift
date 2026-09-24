import AemiTesting
import AppKit
import DiffCore
import SwiftUI
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// A file pane scrolls, whatever its file's length: scrolled to its end, it shows its last line at its top, so even a
/// file shorter than the pane has a range to scroll through. The pane's height follows TextKit's usage bounds, which
/// are empty when a new text is applied and filled in once TextKit lays it out; a pane that kept the height of the
/// empty layout ended a line, less its inset, short of its viewport, and did not scroll at all.
@MainActor
struct FilePaneScrollRangeTests {
    enum Layout: String, CaseIterable, CustomTestStringConvertible {
        case inline, sideBySide
        var testDescription: String { rawValue }
    }

    enum Length: Int, CaseIterable {
        /// Shorter than the pane.
        case short = 12
        /// Several panes long.
        case long = 120
    }

    @Test(arguments: Layout.allCases, [true, false])
    func `a new file pane scrolls its last line up to its top, however long its file`(
        layout: Layout, wrapsLines: Bool
    ) throws {
        for length in Length.allCases {
            let sut = HostedPanes(showing: Self.render(length), layout: layout, wrapsLines: wrapsLines)
            try sut.expectEveryPaneScrollsToItsLastLine("\(length.rawValue) lines")
        }
    }

    /// The temporary tab shows the next file in the pane that showed the last one.
    @Test(arguments: Layout.allCases, [true, false])
    func `a file pane that shows a shorter file next scrolls its last line up to its top`(
        layout: Layout, wrapsLines: Bool
    ) throws {
        let sut = HostedPanes(showing: Self.render(.long), layout: layout, wrapsLines: wrapsLines)

        sut.show(Self.render(.short))

        try sut.expectEveryPaneScrollsToItsLastLine("the shorter file")
    }

    /// `length` short lines, one of them changed, so both sides and the inline text hold every line.
    private static func render(_ length: Length) -> RenderedDiff {
        let lines = (1 ... length.rawValue).map { "let value\($0) = \($0)" }
        var changed = lines
        changed[length.rawValue / 2] = "let changed = true"
        return DiffRenderer.render(
            oldText: lines.joined(separator: "\n") + "\n", newText: changed.joined(separator: "\n") + "\n",
            language: .plain)
    }
}

/// The file panes of one layout, hosted as the detail area hosts them, in a window that is never ordered in.
@MainActor
private final class HostedPanes {
    private let window: NSWindow
    private let host: NSHostingView<Panes>
    private let layout: FilePaneScrollRangeTests.Layout
    private let wrapsLines: Bool
    /// Keeps the two sides in step, on a clock that never moves: nothing here waits for their alignment.
    private let controller: SplitPaneController

    init(showing rendered: RenderedDiff, layout: FilePaneScrollRangeTests.Layout, wrapsLines: Bool) {
        let controller = SplitPaneController(clock: TestClock(), taskProvider: TaskProviderSpy.tolerant())
        self.layout = layout
        self.wrapsLines = wrapsLines
        self.controller = controller
        host = NSHostingView(
            rootView: Panes(rendered: rendered, layout: layout, wrapsLines: wrapsLines, controller: controller))
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600), styleMask: [.borderless], backing: .buffered,
            defer: false)
        window.contentView = host
        settle()
    }

    private func pane(_ rendered: RenderedDiff) -> Panes {
        Panes(rendered: rendered, layout: layout, wrapsLines: wrapsLines, controller: controller)
    }

    /// Shows another file in the same panes, as the temporary tab does.
    func show(_ rendered: RenderedDiff) {
        host.rootView = pane(rendered)
        settle()
    }

    /// Each pane's document runs past its viewport by exactly what puts its last line at the viewport's top.
    func expectEveryPaneScrollsToItsLastLine(_ comment: Comment, sourceLocation: SourceLocation = #_sourceLocation)
        throws
    {
        try expectEachFilePaneScrollsToItsLastLine(
            in: host, count: layout == .inline ? 1 : 2, comment, sourceLocation: sourceLocation)
    }

    /// Lays out and displays what needs it, and lets the run loop turn once, as it does between two events.
    private func settle() {
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0, true)
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
    }
}

/// Expects `count` file panes under `root`, each of whose documents runs past its viewport by exactly what puts its
/// last line at the viewport's top.
@MainActor
func expectEachFilePaneScrollsToItsLastLine(
    in root: NSView, count: Int, _ comment: Comment, sourceLocation: SourceLocation = #_sourceLocation
) throws {
    let textViews = subviews(of: DiffPaneTextView.self, in: root)
    try #require(textViews.count == count, comment, sourceLocation: sourceLocation)
    for textView in textViews {
        let clip = try #require(textView.enclosingScrollView?.contentView, sourceLocation: sourceLocation)
        let rendered = try #require(
            subviews(of: DiffGutterView.self, in: root).first { $0.source === textView }?.rendered,
            sourceLocation: sourceLocation)
        let lastLineTop = textView.textContainerInset.height + CGFloat(rendered.rows.count - 1) * rendered.lineHeight
        let endOffset = textView.frame.height - clip.bounds.height
        #expect(endOffset > 0, "\(comment): nothing to scroll", sourceLocation: sourceLocation)
        #expect(
            abs(lastLineTop - endOffset) < 1,
            "\(comment): scrolled to its end, the pane's top is at \(endOffset), its last line at \(lastLineTop)",
            sourceLocation: sourceLocation)
    }
}

/// Every view of `type` in `view`'s tree, `view` included.
@MainActor
private func subviews<View: NSView>(of type: View.Type, in view: NSView) -> [View] {
    let own: [View] = (view as? View).map { [$0] } ?? []
    return own + view.subviews.flatMap { subviews(of: type, in: $0) }
}

/// One file's panes: the inline pane, or the two sides next to each other.
private struct Panes: View {
    let rendered: RenderedDiff
    let layout: FilePaneScrollRangeTests.Layout
    let wrapsLines: Bool
    let controller: SplitPaneController?

    var body: some View {
        switch layout {
            case .inline:
                if let unified = rendered.unified {
                    DiffTextView(rendered: unified, gutter: .dual, wrapsLines: wrapsLines)
                }
            case .sideBySide:
                if let old = rendered.old, let new = rendered.new {
                    HStack(spacing: 0) {
                        DiffTextView(rendered: old, gutter: .old, wrapsLines: wrapsLines, splitController: controller)
                        DiffTextView(rendered: new, gutter: .new, wrapsLines: wrapsLines, splitController: controller)
                    }
                }
        }
    }
}

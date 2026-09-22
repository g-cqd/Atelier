import AemiTesting
import AppKit
import DiffCore
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// Counts calls and tracks concurrency of a fake documentation lookup: `resolve` sleeps a little, like a real
/// lookup would, so a test can observe whether two calls ever overlap.
private actor ResolverSpy {
    private(set) var calls: [HoverHit] = []
    private(set) var maxConcurrent = 0
    private var concurrent = 0
    var delay: Duration = .milliseconds(20)
    var content: HoverDocument? = HoverDocument(summary: NSAttributedString(string: "docs"))

    func resolve(_ hit: HoverHit) async -> HoverDocument? {
        concurrent += 1
        maxConcurrent = max(maxConcurrent, concurrent)
        try? await Task.sleep(for: delay)
        concurrent -= 1
        calls.append(hit)
        return content
    }
}

@MainActor
private final class WindowRetainer {
    private var windows: [NSWindow] = []
    func append(_ window: NSWindow) { windows.append(window) }
}

@MainActor
struct DocHoverControllerTests {
    private let text = "let alphaBeta = 1\nlet gammaDelta = 2\n"
    /// `NSWindow` does not retain its content view's window relationship beyond what AppKit itself holds; nothing
    /// else in the test keeps the window alive, so it would be deallocated (and the text view's `window` reset to
    /// nil) right after the helper returns without this.
    private let retainedWindows = WindowRetainer()

    private func rendered() throws -> RenderedText {
        try #require(DiffRenderer.render(oldText: text, newText: text, language: .plain).new)
    }

    private func textView(showing rendered: RenderedText) -> NSTextView {
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.textContainerInset = NSSize(width: 0, height: DiffPaneMetrics.containerInset)
        textView.textContainer?.lineFragmentPadding = DiffPaneMetrics.lineFragmentPadding
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.size = NSSize(width: 800, height: DiffPaneMetrics.unboundedExtent)
        textView.textContentStorage?.textStorage?.setAttributedString(rendered.attributed)
        textView.textLayoutManager?.ensureLayout(for: textView.textLayoutManager!.documentRange)
        // NSPopover needs a real window to show against.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 200), styleMask: [.borderless], backing: .buffered,
            defer: false)
        window.contentView?.addSubview(textView)
        retainedWindows.append(window)
        return textView
    }

    /// Wraps `textView` in a real `NSScrollView` (also hosted in a real, retained window), the way a diff pane
    /// actually attaches it -- ``DocHoverController/attach(to:rendered:)`` only observes
    /// `NSView.boundsDidChangeNotification` from an enclosing scroll view's clip view, so a scroll-follow test
    /// needs one.
    private func scrollingTextView(showing rendered: RenderedText) -> (scrollView: NSScrollView, textView: NSTextView) {
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.textContainerInset = NSSize(width: 0, height: DiffPaneMetrics.containerInset)
        textView.textContainer?.lineFragmentPadding = DiffPaneMetrics.lineFragmentPadding
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.size = NSSize(width: 800, height: DiffPaneMetrics.unboundedExtent)
        textView.textContentStorage?.textStorage?.setAttributedString(rendered.attributed)
        textView.textLayoutManager?.ensureLayout(for: textView.textLayoutManager!.documentRange)
        textView.frame = NSRect(x: 0, y: 0, width: 800, height: rendered.lineHeight * CGFloat(rendered.rows.count) + 40)

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 100))
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 100), styleMask: [.borderless], backing: .buffered,
            defer: false)
        window.contentView?.addSubview(scrollView)
        retainedWindows.append(window)
        return (scrollView, textView)
    }

    /// Column 8 sits inside "alphaBeta" on row 0; column 8 of row 1 sits inside "gammaDelta".
    private func point(row: Int, column: Int, in rendered: RenderedText) -> NSPoint {
        let charWidth = ("0" as NSString).size(withAttributes: [.font: rendered.palette.font]).width
        return NSPoint(
            x: DiffPaneMetrics.lineFragmentPadding + (CGFloat(column) + 0.5) * charWidth,
            y: DiffPaneMetrics.containerInset + (CGFloat(row) + 0.5) * rendered.lineHeight)
    }

    private func makeSUT(debounce: Duration = .milliseconds(5)) -> (
        controller: DocHoverController, spy: ResolverSpy, taskProvider: TaskProviderSpy
    ) {
        let taskProvider = TaskProviderSpy()
        let controller = DocHoverController(taskProvider: taskProvider, debounce: debounce)
        let spy = ResolverSpy()
        controller.resolve = { hit in await spy.resolve(hit) }
        return (controller, spy, taskProvider)
    }

    @Test
    func `two rapid moves to different hits resolve only the last`() async throws {
        let rendered = try rendered()
        let view = textView(showing: rendered)
        let (controller, spy, taskProvider) = makeSUT()
        controller.attach(to: view) { rendered }

        controller.pointerMoved(to: point(row: 0, column: 8, in: rendered))
        controller.pointerMoved(to: point(row: 1, column: 8, in: rendered))
        try await taskProvider.waitForAllTasks(timeout: .seconds(2))

        let calls = await spy.calls
        #expect(calls.count == 1)
        #expect(calls.first?.row == 1)
    }

    @Test
    func `moving within the same identifier does not re-resolve`() async throws {
        let rendered = try rendered()
        let view = textView(showing: rendered)
        let (controller, spy, taskProvider) = makeSUT()
        controller.attach(to: view) { rendered }

        controller.pointerMoved(to: point(row: 0, column: 8, in: rendered))
        try await taskProvider.waitForAllTasks(timeout: .seconds(2))
        controller.pointerMoved(to: point(row: 0, column: 8, in: rendered))
        try await taskProvider.waitForAllTasks(timeout: .seconds(2))

        #expect(await spy.calls.count == 1)
        #expect(taskProvider.spawnedTaskCount == 1)
    }

    @Test
    func `invalidating before the debounce elapses discards the resolution and shows nothing`() async throws {
        let rendered = try rendered()
        let view = textView(showing: rendered)
        let (controller, spy, taskProvider) = makeSUT()
        controller.attach(to: view) { rendered }

        controller.pointerMoved(to: point(row: 0, column: 8, in: rendered))
        controller.invalidate()
        try await taskProvider.waitForAllTasks(timeout: .seconds(2))

        #expect(await spy.calls.isEmpty)
        #expect(controller.isPopoverVisible == false)
    }

    @Test
    func `disabling the controller never calls the resolver`() async throws {
        let rendered = try rendered()
        let view = textView(showing: rendered)
        let (controller, spy, taskProvider) = makeSUT()
        controller.isEnabled = false
        controller.attach(to: view) { rendered }

        controller.pointerMoved(to: point(row: 0, column: 8, in: rendered))
        try? await Task.sleep(for: .milliseconds(50))

        #expect(await spy.calls.isEmpty)
        #expect(taskProvider.spawnedTaskCount == 0)
    }

    // MARK: Scroll-follow

    private func manyLinesRendered(count: Int = 40) throws -> RenderedText {
        let manyLines = (0 ..< count).map { "let identifier\($0) = \($0)\n" }.joined()
        return try #require(DiffRenderer.render(oldText: manyLines, newText: manyLines, language: .plain).new)
    }

    @Test
    func `scrolling while the panel is visible keeps it open, repositioned, not closed`() async throws {
        let rendered = try manyLinesRendered()
        let (scrollView, view) = scrollingTextView(showing: rendered)
        let (controller, _, taskProvider) = makeSUT()
        controller.attach(to: view) { rendered }

        controller.pointerMoved(to: point(row: 0, column: 8, in: rendered))
        try await taskProvider.waitForAllTasks(timeout: .seconds(2))
        #expect(controller.isPopoverVisible == true)

        // A small scroll: row 0's anchor stays within the 100pt-tall viewport.
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 5))
        scrollView.reflectScrolledClipView(scrollView.contentView)

        #expect(controller.isPopoverVisible == true)
    }

    @Test
    func `scrolling the hovered identifier entirely out of view closes the panel`() async throws {
        let rendered = try manyLinesRendered()
        let (scrollView, view) = scrollingTextView(showing: rendered)
        let (controller, _, taskProvider) = makeSUT()
        controller.attach(to: view) { rendered }

        controller.pointerMoved(to: point(row: 0, column: 8, in: rendered))
        try await taskProvider.waitForAllTasks(timeout: .seconds(2))
        #expect(controller.isPopoverVisible == true)

        // Scroll far enough that row 0 is nowhere near the 100pt-tall viewport any more.
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: rendered.lineHeight * 30))
        scrollView.reflectScrolledClipView(scrollView.contentView)

        #expect(controller.isPopoverVisible == false)
    }

    @Test
    func `resolution never runs more than one at a time`() async throws {
        let rendered = try rendered()
        let view = textView(showing: rendered)
        let (controller, spy, taskProvider) = makeSUT()
        controller.attach(to: view) { rendered }

        controller.pointerMoved(to: point(row: 0, column: 4, in: rendered))
        controller.pointerMoved(to: point(row: 0, column: 8, in: rendered))
        controller.pointerMoved(to: point(row: 1, column: 8, in: rendered))
        try await taskProvider.waitForAllTasks(timeout: .seconds(2))

        #expect(await spy.maxConcurrent <= 1)
    }
}

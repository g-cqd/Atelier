import AemiTesting
import AppKit
import DiffCore
import Synchronization
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// A fake documentation lookup that records its calls and how many of them ever overlap. A holding spy keeps each
/// lookup in flight until the test releases it, so a newer hover can arrive while an older lookup still runs.
private final class ResolverSpy: Sendable {
    private struct State {
        var calls: [HoverHit] = []
        var inFlight = 0
        var maxInFlight = 0
        var held: [CheckedContinuation<Void, Never>] = []
    }

    private let state = Mutex(State())
    private let holdsLookups: Bool
    private let content = HoverDocument(summary: NSAttributedString(string: "docs"))
    /// Each lookup as it starts; a held lookup is recorded once it can be released.
    let started = CountProbe<HoverHit>()

    init(holdsLookups: Bool) {
        self.holdsLookups = holdsLookups
    }

    var calls: [HoverHit] { state.withLock(\.calls) }
    var maxInFlight: Int { state.withLock(\.maxInFlight) }

    func resolve(_ hit: HoverHit) async -> HoverDocument? {
        state.withLock { state in
            state.inFlight += 1
            state.maxInFlight = max(state.maxInFlight, state.inFlight)
        }
        if holdsLookups {
            // Deaf to cancellation, as a real lookup may be: a superseded hover does not stop the one in flight.
            await withCheckedContinuation { continuation in
                state.withLock { $0.held.append(continuation) }
                started.record(hit)
            }
        } else {
            started.record(hit)
        }
        state.withLock { state in
            state.inFlight -= 1
            state.calls.append(hit)
        }
        return content
    }

    /// Lets the oldest held lookup return; a no-op when none is held.
    func releaseOldest() {
        let oldest = state.withLock { $0.held.isEmpty ? nil : $0.held.removeFirst() }
        oldest?.resume()
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
    /// Keeps the test windows alive; nothing else holds them once a helper returns.
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
        if let layoutManager = textView.textLayoutManager {
            layoutManager.ensureLayout(for: layoutManager.documentRange)
        }
        // The panel needs a real window to attach to.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 200), styleMask: [.borderless], backing: .buffered,
            defer: false)
        window.contentView?.addSubview(textView)
        retainedWindows.append(window)
        return textView
    }

    /// A text view in a real scroll view and window, since the controller follows scrolls through the clip view.
    private func scrollingTextView(showing rendered: RenderedText) -> (scrollView: NSScrollView, textView: NSTextView) {
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.textContainerInset = NSSize(width: 0, height: DiffPaneMetrics.containerInset)
        textView.textContainer?.lineFragmentPadding = DiffPaneMetrics.lineFragmentPadding
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.size = NSSize(width: 800, height: DiffPaneMetrics.unboundedExtent)
        textView.textContentStorage?.textStorage?.setAttributedString(rendered.attributed)
        if let layoutManager = textView.textLayoutManager {
            layoutManager.ensureLayout(for: layoutManager.documentRange)
        }
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

    private func makeSUT(debounce: Duration = .milliseconds(5), holdingLookups: Bool = false) -> (
        controller: DocHoverController, spy: ResolverSpy, taskProvider: TaskProviderSpy
    ) {
        let taskProvider = TaskProviderSpy.tolerant()
        let controller = DocHoverController(taskProvider: taskProvider, debounce: debounce)
        let spy = ResolverSpy(holdsLookups: holdingLookups)
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
        try await taskProvider.waitForAllTasks()

        let calls = spy.calls
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
        try await taskProvider.waitForAllTasks()
        controller.pointerMoved(to: point(row: 0, column: 8, in: rendered))
        try await taskProvider.waitForAllTasks()

        #expect(spy.calls.count == 1)
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
        try await taskProvider.waitForAllTasks()

        #expect(spy.calls.isEmpty)
        #expect(controller.isPanelVisible == false)
    }

    /// Hovering a pane whose render has gone away costs nothing: no hit-test, no task, no resolver call. A lookup
    /// runs only inside a spawned task, so no spawn proves no call, now or later.
    @Test
    func `pointerMoved with no rendered content does zero resolver or hit-test work`() throws {
        let rendered = try rendered()
        let view = textView(showing: rendered)
        let (controller, spy, taskProvider) = makeSUT()
        controller.attach(to: view) { nil }

        controller.pointerMoved(to: point(row: 0, column: 8, in: rendered))

        #expect(taskProvider.spawnedTaskCount == 0)
        #expect(spy.started.isEmpty)
        #expect(controller.isPanelVisible == false)
    }

    /// A lookup runs only inside a spawned task, so no spawn proves no call, now or later.
    @Test
    func `disabling the controller never calls the resolver`() throws {
        let rendered = try rendered()
        let view = textView(showing: rendered)
        let (controller, spy, taskProvider) = makeSUT()
        controller.isEnabled = false
        controller.attach(to: view) { rendered }

        controller.pointerMoved(to: point(row: 0, column: 8, in: rendered))

        #expect(taskProvider.spawnedTaskCount == 0)
        #expect(spy.started.isEmpty)
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
        try await taskProvider.waitForAllTasks()
        #expect(controller.isPanelVisible == true)

        // A small scroll: row 0's anchor stays within the 100pt-tall viewport.
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 5))
        scrollView.reflectScrolledClipView(scrollView.contentView)

        #expect(controller.isPanelVisible == true)
    }

    @Test
    func `scrolling the hovered identifier entirely out of view closes the panel`() async throws {
        let rendered = try manyLinesRendered()
        let (scrollView, view) = scrollingTextView(showing: rendered)
        let (controller, _, taskProvider) = makeSUT()
        controller.attach(to: view) { rendered }

        controller.pointerMoved(to: point(row: 0, column: 8, in: rendered))
        try await taskProvider.waitForAllTasks()
        #expect(controller.isPanelVisible == true)

        // Scroll far enough that row 0 is nowhere near the 100pt-tall viewport any more.
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: rendered.lineHeight * 30))
        scrollView.reflectScrolledClipView(scrollView.contentView)

        #expect(controller.isPanelVisible == false)
    }

    @Test
    func `a bounds-changed notification with no actual scroll offset is a no-op`() async throws {
        let rendered = try manyLinesRendered()
        let (scrollView, view) = scrollingTextView(showing: rendered)
        let (controller, _, taskProvider) = makeSUT()
        controller.attach(to: view) { rendered }

        controller.pointerMoved(to: point(row: 0, column: 8, in: rendered))
        try await taskProvider.waitForAllTasks()
        #expect(controller.isPanelVisible == true)

        // Same origin as already reflected: a spurious notification, not a scroll.
        NotificationCenter.default.post(
            name: NSView.boundsDidChangeNotification, object: scrollView.contentView)

        #expect(controller.isPanelVisible == true)
    }

    /// The older lookup ignores its cancellation and runs on, as a slow language server may; the newer hover's lookup
    /// starts only once it returns, and the newer hover is the one shown.
    @Test
    func `a hover over a lookup still in flight resolves once that lookup returns, one lookup at a time`()
        async throws
    {
        let rendered = try rendered()
        let view = textView(showing: rendered)
        let (controller, spy, taskProvider) = makeSUT(holdingLookups: true)
        controller.attach(to: view) { rendered }

        controller.pointerMoved(to: point(row: 0, column: 8, in: rendered))
        try await spy.started.wait(forAtLeast: 1, timeout: TaskProviderSpy.failureBound)
        controller.pointerMoved(to: point(row: 1, column: 8, in: rendered))
        spy.releaseOldest()
        try await spy.started.wait(forAtLeast: 2, timeout: TaskProviderSpy.failureBound)
        spy.releaseOldest()
        try await taskProvider.waitForAllTasks()

        #expect(spy.maxInFlight == 1)
        #expect(spy.calls.map(\.row) == [0, 1])
        #expect(controller.isPanelVisible == true)
    }

    // MARK: Staying open under the pointer (HOVER-20, criterion 7)

    /// A controller whose panel orders no window in, on a text view in a window placed well inside the screen, so the
    /// panel opens below its identifier, and a test clock that drives both the debounce and the grace delay.
    private struct StayOpenSUT {
        let controller: DocHoverController
        let panel: HoverDocPanel
        let spy: ResolverSpy
        let taskProvider: TaskProviderSpy
        let clock: TestClock
        let textView: NSTextView
        let rendered: RenderedText
    }

    private func makeStayOpenSUT() throws -> StayOpenSUT {
        let rendered = try rendered()
        let view = textView(showing: rendered)
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 200)
        try #require(view.window).setFrame(NSRect(x: 200, y: 400, width: 800, height: 200), display: false)
        let taskProvider = TaskProviderSpy.tolerant()
        let clock = TestClock()
        let panel = HoverDocPanel(ordersWindowIn: false)
        let controller = DocHoverController(
            clock: clock, taskProvider: taskProvider, debounce: .milliseconds(300), panel: panel)
        let spy = ResolverSpy(holdsLookups: false)
        controller.resolve = { hit in await spy.resolve(hit) }
        controller.attach(to: view) { rendered }
        return StayOpenSUT(
            controller: controller, panel: panel, spy: spy, taskProvider: taskProvider, clock: clock, textView: view,
            rendered: rendered)
    }

    /// Rests on `alphaBeta` through the debounce, so its panel shows.
    private func showPanelOnRowZero(_ sut: StayOpenSUT) async throws {
        let mark = sut.clock.registrationMark()
        sut.controller.pointerMoved(to: point(row: 0, column: 8, in: sut.rendered))
        try await sut.clock.expectSleepers(after: mark)
        sut.clock.advance(by: sut.controller.debounce)
        try await sut.taskProvider.waitForAllTasks()
        try #require(sut.controller.isPanelVisible)
    }

    /// Row 0 at `column`, `fraction` of the way down the line.
    private func point(row: Int, column: Double, lineFraction fraction: CGFloat, in rendered: RenderedText) -> NSPoint {
        let charWidth = ("0" as NSString).size(withAttributes: [.font: rendered.palette.font]).width
        return NSPoint(
            x: DiffPaneMetrics.lineFragmentPadding + CGFloat(column) * charWidth,
            y: DiffPaneMetrics.containerInset + (CGFloat(row) + fraction) * rendered.lineHeight)
    }

    /// Over the space between `let` and `alphaBeta`, in the line's top quarter: off the symbol, the corridor below it
    /// and the panel.
    private func awayPoint(_ sut: StayOpenSUT) -> NSPoint {
        point(row: 0, column: 3.5, lineFraction: 0.25, in: sut.rendered)
    }

    @Test
    func `moving from the symbol through the corridor onto the panel keeps it open`() async throws {
        let sut = try makeStayOpenSUT()
        try await showPanelOnRowZero(sut)

        // Past `alphaBeta`, over ` = 1`, in the lower half of its line, which the panel below lies along.
        sut.controller.pointerMoved(to: point(row: 0, column: 14.5, lineFraction: 0.85, in: sut.rendered))
        sut.panel.pointerEntered()
        sut.clock.advance(by: .seconds(5))
        try await sut.taskProvider.waitForAllTasks()

        #expect(sut.controller.isPanelVisible)
        #expect(sut.spy.calls.count == 1)
    }

    @Test
    func `leaving the symbol, the corridor and the panel closes it after the grace delay, and not before`()
        async throws
    {
        let sut = try makeStayOpenSUT()
        try await showPanelOnRowZero(sut)

        let mark = sut.clock.registrationMark()
        sut.controller.pointerMoved(to: awayPoint(sut))
        try await sut.clock.expectSleepers(after: mark)
        sut.clock.advance(by: DocHoverController.closeGraceDelay - .milliseconds(1))
        #expect(sut.controller.isPanelVisible)

        sut.clock.advance(by: .milliseconds(1))
        try await sut.taskProvider.waitForAllTasks()
        #expect(!sut.controller.isPanelVisible)
    }

    enum Return: CaseIterable, Sendable { case symbol, panel }

    @Test(arguments: Return.allCases)
    func `coming back within the grace delay cancels the close`(to destination: Return) async throws {
        let sut = try makeStayOpenSUT()
        try await showPanelOnRowZero(sut)

        let mark = sut.clock.registrationMark()
        sut.controller.pointerMoved(to: awayPoint(sut))
        try await sut.clock.expectSleepers(after: mark)
        sut.clock.advance(by: DocHoverController.closeGraceDelay / 2)
        switch destination {
            case .symbol: sut.controller.pointerMoved(to: point(row: 0, column: 8, in: sut.rendered))
            case .panel: sut.panel.pointerEntered()
        }
        sut.clock.advance(by: .seconds(5))
        try await sut.taskProvider.waitForAllTasks()

        #expect(sut.controller.isPanelVisible)
        // Back on its own symbol, the panel is not looked up again.
        #expect(sut.spy.calls.count == 1)
    }

    @Test
    func `leaving the pane for anywhere but the panel closes it after the grace delay`() async throws {
        let sut = try makeStayOpenSUT()
        try await showPanelOnRowZero(sut)

        let mark = sut.clock.registrationMark()
        sut.controller.pointerLeftTextView()
        try await sut.clock.expectSleepers(after: mark)
        #expect(sut.controller.isPanelVisible)
        sut.clock.advance(by: DocHoverController.closeGraceDelay)
        try await sut.taskProvider.waitForAllTasks()

        #expect(!sut.controller.isPanelVisible)
    }

    @Test
    func `leaving the panel closes it after the grace delay`() async throws {
        let sut = try makeStayOpenSUT()
        try await showPanelOnRowZero(sut)
        sut.panel.pointerEntered()

        let mark = sut.clock.registrationMark()
        sut.panel.pointerExited()
        try await sut.clock.expectSleepers(after: mark)
        #expect(sut.controller.isPanelVisible)
        sut.clock.advance(by: DocHoverController.closeGraceDelay)
        try await sut.taskProvider.waitForAllTasks()

        #expect(!sut.controller.isPanelVisible)
    }

    /// Over the panel, the pointer is not over the text: a move the pane still reports looks nothing up.
    @Test
    func `while the pointer is over the panel, moves beneath it look nothing up`() async throws {
        let sut = try makeStayOpenSUT()
        try await showPanelOnRowZero(sut)
        let spawned = sut.taskProvider.spawnedTaskCount

        sut.panel.pointerEntered()
        sut.controller.pointerMoved(to: point(row: 1, column: 8, in: sut.rendered))

        #expect(sut.taskProvider.spawnedTaskCount == spawned)
        #expect(sut.controller.isPanelVisible)
    }

    @Test
    func `hovering another symbol replaces the panel after the debounce, the first staying until then`()
        async throws
    {
        let sut = try makeStayOpenSUT()
        try await showPanelOnRowZero(sut)

        let mark = sut.clock.registrationMark()
        sut.controller.pointerMoved(to: point(row: 1, column: 8, in: sut.rendered))
        #expect(sut.controller.isPanelVisible)
        try await sut.clock.expectSleepers(after: mark)
        sut.clock.advance(by: sut.controller.debounce)
        try await sut.taskProvider.waitForAllTasks()

        #expect(sut.spy.calls.map(\.row) == [0, 1])
        #expect(sut.controller.isPanelVisible)
        // The new symbol's panel does not close on the grace delay the old one's would have started.
        sut.clock.advance(by: .seconds(5))
        try await sut.taskProvider.waitForAllTasks()
        #expect(sut.controller.isPanelVisible)
    }

    @Test
    func `escape closes the panel`() async throws {
        let sut = try makeStayOpenSUT()
        try await showPanelOnRowZero(sut)
        let escape = try #require(
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))

        #expect(sut.controller.handleLocalEvent(escape) == nil)
        #expect(!sut.controller.isPanelVisible)
    }

    @Test
    func `a click outside the panel closes it and still reaches its target`() async throws {
        let sut = try makeStayOpenSUT()
        try await showPanelOnRowZero(sut)
        let click = try #require(
            NSEvent.mouseEvent(
                with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1))

        #expect(sut.controller.handleLocalEvent(click) === click)
        #expect(!sut.controller.isPanelVisible)
    }

    @Test
    func `the pane's window resigning key closes the panel`() async throws {
        let sut = try makeStayOpenSUT()
        try await showPanelOnRowZero(sut)

        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: sut.textView.window)

        #expect(!sut.controller.isPanelVisible)
    }

    @Test
    func `a lookup pending when the pointer reaches the panel does not replace it`() async throws {
        let sut = try makeStayOpenSUT()
        try await showPanelOnRowZero(sut)

        let mark = sut.clock.registrationMark()
        sut.controller.pointerMoved(to: point(row: 1, column: 8, in: sut.rendered))
        try await sut.clock.expectSleepers(after: mark)
        sut.panel.pointerEntered()
        sut.clock.advance(by: sut.controller.debounce)
        try await sut.taskProvider.waitForAllTasks()

        #expect(sut.spy.calls.map(\.row) == [0])
        #expect(sut.controller.isPanelVisible)
    }

    @Test
    func `a scroll drops a pending hover while a panel shows`() async throws {
        let rendered = try manyLinesRendered()
        let (scrollView, view) = scrollingTextView(showing: rendered)
        let taskProvider = TaskProviderSpy.tolerant()
        let clock = TestClock()
        let controller = DocHoverController(
            clock: clock, taskProvider: taskProvider, debounce: .milliseconds(300),
            panel: HoverDocPanel(ordersWindowIn: false))
        let spy = ResolverSpy(holdsLookups: false)
        controller.resolve = { hit in await spy.resolve(hit) }
        controller.attach(to: view) { rendered }
        var mark = clock.registrationMark()
        controller.pointerMoved(to: point(row: 0, column: 8, in: rendered))
        try await clock.expectSleepers(after: mark)
        clock.advance(by: controller.debounce)
        try await taskProvider.waitForAllTasks()
        try #require(controller.isPanelVisible)

        mark = clock.registrationMark()
        controller.pointerMoved(to: point(row: 1, column: 8, in: rendered))
        try await clock.expectSleepers(after: mark)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 5))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        clock.advance(by: controller.debounce)
        try await taskProvider.waitForAllTasks()

        #expect(spy.calls.map(\.row) == [0])
    }
}

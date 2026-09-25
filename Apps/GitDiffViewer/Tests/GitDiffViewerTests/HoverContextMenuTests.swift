import AemiTesting
import AppKit
import AtelierDiagnostics
import DiffCore
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// A context menu over a pane's text starts with Show Documentation over an identifier and Show Issue over an
/// underlined finding (book HOVER-14). The single-file view and the card list both show their text in a
/// ``DiffPaneTextView`` beside a ``DiffGutterView`` in a ``DiffPaneView``, under a ``DocHoverController``, as here.
@MainActor
struct HoverContextMenuTests {
    /// "alphaValue" is columns 4 to 13 of row 0, zero-based; "gamma" columns 4 to 8 of row 1.
    fileprivate static let text = "let alphaValue = betaValue\nlet gamma = 1\n"
    fileprivate static let alpha = Finding(
        tool: .swiftlint, ruleID: "alpha", message: "message alpha", file: "a.swift", line: 1, column: 5, endLine: 1,
        endColumn: 15, severity: .warning)

    @Test
    func `a context menu over an underlined identifier offers Show Documentation and Show Issue`() throws {
        let sut = try Pane()

        let items = sut.controller.contextMenuItems(at: sut.point(row: 0, column: 8))

        #expect(items.map(\.title) == ["Show Documentation", "Show Issue"])
    }

    @Test
    func `a context menu over an identifier with no finding offers Show Documentation alone`() throws {
        let sut = try Pane()

        let items = sut.controller.contextMenuItems(at: sut.point(row: 1, column: 6))

        #expect(items.map(\.title) == ["Show Documentation"])
    }

    @Test
    func `Show Issue opens the finding's popover, as a click on its line number does`() throws {
        let sut = try Pane()
        let items = sut.controller.contextMenuItems(at: sut.point(row: 0, column: 8))

        try sut.perform(#require(items.first { $0.title == "Show Issue" }))

        #expect(sut.clicks.map(\.row) == [0])
        #expect(sut.clicks.first?.findings == [Self.alpha])
    }

    @Test
    func `Show Documentation opens the hover panel for the symbol without waiting for the debounce`() async throws {
        let sut = try Pane()
        let items = sut.controller.contextMenuItems(at: sut.point(row: 0, column: 8))

        try sut.perform(#require(items.first { $0.title == "Show Documentation" }))
        try await sut.taskProvider.waitForAllTasks()

        #expect(sut.controller.isPanelVisible)
    }

    @Test
    func `the text view's context menu starts with the items, apart from its own`() throws {
        let sut = try Pane()
        let location = sut.textView.convert(sut.point(row: 0, column: 8), to: nil)
        let event = try #require(
            NSEvent.mouseEvent(
                with: .rightMouseDown, location: location, modifierFlags: [], timestamp: 0,
                windowNumber: sut.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))

        let menu = try #require(sut.textView.menu(for: event))

        #expect(menu.items.prefix(2).map(\.title) == ["Show Documentation", "Show Issue"])
        #expect(menu.items.count > 2 && menu.items[2].isSeparatorItem)
    }
}

/// A pane of ``HoverContextMenuTests/text`` with ``HoverContextMenuTests/alpha`` underlined on row 0, whose gutter
/// records its clicks, in a borderless window that is never ordered in.
@MainActor
private final class Pane {
    let window: NSWindow
    let textView = DiffPaneTextView(usingTextLayoutManager: true)
    let controller: DocHoverController
    let taskProvider = TaskProviderSpy.tolerant()
    private let rendered: RenderedText
    private(set) var clicks: [(row: Int, findings: [Finding])] = []

    init() throws {
        let rendered = try #require(
            DiffRenderer.render(
                oldText: HoverContextMenuTests.text, newText: HoverContextMenuTests.text, language: .plain
            )
            .new)
        self.rendered = rendered
        textView.textContainerInset = NSSize(width: 0, height: DiffPaneMetrics.containerInset)
        textView.textContainer?.lineFragmentPadding = DiffPaneMetrics.lineFragmentPadding
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.size = NSSize(width: 600, height: DiffPaneMetrics.unboundedExtent)
        textView.textContentStorage?.textStorage?.setAttributedString(rendered.attributed)
        textView.frame = NSRect(x: 0, y: 0, width: 600, height: 100)

        let gutter = DiffGutterView(clipView: nil)
        gutter.source = textView
        gutter.rendered = rendered
        gutter.overlay = DiagnosticOverlay(
            rows: [0: .init(severity: .warning, count: 1, findings: [HoverContextMenuTests.alpha], squiggles: [])])
        let pane = DiffPaneView(gutterView: gutter, scrollView: nil, contentView: textView, minimapView: MinimapView())
        pane.frame = NSRect(x: 0, y: 0, width: 640, height: 100)
        window = NSWindow(
            contentRect: pane.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(pane)
        pane.layoutSubtreeIfNeeded()
        if let layoutManager = textView.textLayoutManager {
            layoutManager.ensureLayout(for: layoutManager.documentRange)
        }

        controller = DocHoverController(
            clock: TestClock(), taskProvider: taskProvider, panel: HoverDocPanel(ordersWindowIn: false))
        controller.resolve = { _ in HoverDocument(title: "doc") }
        controller.attach(to: textView) { rendered }
        gutter.onDiagnosticClick = { [weak self] row, findings, _, _ in self?.clicks.append((row, findings)) }
    }

    isolated deinit {
        controller.detach()
        window.close()
    }

    /// The middle of `column`'s character on `row`, in the text view's coordinates.
    func point(row: Int, column: Int) -> NSPoint {
        let charWidth = ("0" as NSString).size(withAttributes: [.font: rendered.palette.font]).width
        return NSPoint(
            x: DiffPaneMetrics.lineFragmentPadding + (CGFloat(column) + 0.5) * charWidth,
            y: DiffPaneMetrics.containerInset + (CGFloat(row) + 0.5) * rendered.lineHeight)
    }

    /// Chooses `item`, as the menu does.
    func perform(_ item: NSMenuItem) throws {
        let target = try #require(item.target as? NSObject)
        let action = try #require(item.action)
        _ = target.perform(action, with: item)
    }
}

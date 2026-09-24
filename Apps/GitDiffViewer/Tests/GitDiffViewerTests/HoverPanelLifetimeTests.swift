import AemiTesting
import AppKit
import DiffCore
import SwiftUI
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// A pane builds its hover panel on the first hover and releases it as it goes: switching between the file list and a
/// file creates and tears down panes by the dozen, and a panel built with each one piled up.
@MainActor
struct HoverPanelLifetimeTests {
    private let text = "let alphaBeta = 1\nlet gammaDelta = 2\n"

    /// Synchronous from the first count to the last, so no other suite's panel comes or goes in between.
    @Test
    func `panes coming and going hold no hover panel until one is hovered`() throws {
        let rendered = try #require(DiffRenderer.render(oldText: text, newText: text, language: .plain).unified)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 300), styleMask: [.borderless], backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let before = HoverDocPanel.liveCount

        for _ in 0 ..< 5 {
            autoreleasepool {
                window.contentView = NSHostingView(rootView: DiffTextView(rendered: rendered, gutter: .dual))
                window.contentView?.layoutSubtreeIfNeeded()
            }
            #expect(HoverDocPanel.liveCount == before)
        }
        autoreleasepool { window.contentView = NSView() }

        #expect(HoverDocPanel.liveCount == before)
    }

    @Test
    func `a hovered pane's panel is released when the pane detaches`() async throws {
        let rendered = try #require(DiffRenderer.render(oldText: text, newText: text, language: .plain).new)
        let (textView, window) = Self.textView(showing: rendered)
        defer { window.close() }
        let taskProvider = TaskProviderSpy.tolerant()
        let clock = TestClock()
        let controller = DocHoverController(
            clock: clock, taskProvider: taskProvider, debounce: .milliseconds(300),
            panel: HoverDocPanel(ordersWindowIn: false))
        controller.resolve = { _ in HoverDocument(summary: NSAttributedString(string: "docs")) }
        controller.attach(to: textView) { rendered }
        #expect(controller.panelForTests == nil)

        let mark = clock.registrationMark()
        controller.pointerMoved(to: Self.point(row: 0, column: 8, in: rendered))
        try await clock.expectSleepers(after: mark)
        clock.advance(by: controller.debounce)
        try await taskProvider.waitForAllTasks()
        try #require(controller.isPanelVisible)
        weak let panel = controller.panelForTests

        autoreleasepool { controller.detach() }

        #expect(panel == nil)
        #expect(!controller.isPanelVisible)
    }

    /// A laid-out text view in a window never ordered in, which the panel needs to attach to.
    private static func textView(showing rendered: RenderedText) -> (NSTextView, NSWindow) {
        let textView = NSTextView(usingTextLayoutManager: true)
        textView.textContainerInset = NSSize(width: 0, height: DiffPaneMetrics.containerInset)
        textView.textContainer?.lineFragmentPadding = DiffPaneMetrics.lineFragmentPadding
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.size = NSSize(width: 800, height: DiffPaneMetrics.unboundedExtent)
        textView.textContentStorage?.textStorage?.setAttributedString(rendered.attributed)
        if let layoutManager = textView.textLayoutManager {
            layoutManager.ensureLayout(for: layoutManager.documentRange)
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 200), styleMask: [.borderless], backing: .buffered,
            defer: false)
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(textView)
        return (textView, window)
    }

    /// The middle of the character at `column` of `row`, in the text view's coordinates.
    private static func point(row: Int, column: Int, in rendered: RenderedText) -> NSPoint {
        let charWidth = ("0" as NSString).size(withAttributes: [.font: rendered.palette.font]).width
        return NSPoint(
            x: DiffPaneMetrics.lineFragmentPadding + (CGFloat(column) + 0.5) * charWidth,
            y: DiffPaneMetrics.containerInset + (CGFloat(row) + 0.5) * rendered.lineHeight)
    }
}

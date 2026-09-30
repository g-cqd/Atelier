import AemiCore
import AemiTesting
import AppKit
import DiffComparison
import DiffCore
import SwiftUI
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// A gap handle held at the edge of a single-file pane keeps revealing at the drag's bounded rate, and the pane scrolls
/// along so the handle stays in view as rows open above it (book DIFF-02). The gutter, the drag's controller and the
/// pane are wired as the window wires them, on a test clock.
@MainActor
@Suite(.mainActorLane)
struct FilePaneGapHoldTests {
    @Test
    func `a half held at the bottom edge of a file pane keeps revealing, its band in view`() async throws {
        let sut = try HeldFilePane()
        let gap = try #require(sut.middleGap())
        // The pane ends just below the band, whose upper half then lies in the edge zone.
        sut.fit(height: (gap.band.maxY + 2).rounded(.up))
        let placed = try #require(sut.middleGap())
        let visible = sut.gutter.visibleRect
        let upper = try #require(GapHandleLayout.handle(placed.marker.handles, in: placed.band).halves.first)
        let start = NSPoint(x: upper.rect.midX, y: upper.rect.midY)
        // Two points down: in the edge zone, short of the half row that would reveal a row by itself.
        let held = NSPoint(x: start.x, y: start.y + 2)
        try #require(held.y > visible.maxY - GapHandleLayout.edgeZone)

        sut.mouse(.leftMouseDown, at: start)
        let hold = sut.clock.registrationMark()
        sut.mouse(.leftMouseDragged, at: held)
        var revealed: [Int] = []
        for step in 1 ... 3 {
            try await sut.clock.expectSleepers(step, after: hold)
            sut.clock.advance(by: GapDrag.slowestHold)
            revealed.append(try #require(try await sut.applied.expectNext()).below)
        }
        sut.mouse(.leftMouseUp, at: held)
        try await sut.taskProvider.waitForAllTasks()

        #expect(revealed == [1, 2, 3])
        let after = try #require(sut.middleGap())
        #expect(after.marker.key == placed.marker.key)
        #expect(sut.scrollOffset > 0)
        #expect(sut.gutter.visibleRect.contains(after.band))
    }
}

extension FilePaneGapHoldTests {
    /// Beneath the tab bar, the pane's top edge lies below the bar, and the edge zone with it (book TAB-09).
    @Test
    func `a half held just below the bars over a file pane keeps revealing`() async throws {
        let bars: CGFloat = 40
        let sut = try HeldFilePane(underBars: bars)
        // Shorter than the text, so it scrolls.
        sut.fit(height: 140)
        let gap = try #require(sut.middleGap())
        // The gap's band lies just below the bars.
        sut.scroll(by: gap.band.minY - (bars + 2))
        let placed = try #require(sut.middleGap())
        let lower = try #require(GapHandleLayout.handle(placed.marker.handles, in: placed.band).halves.last)
        let start = NSPoint(x: lower.rect.midX, y: lower.rect.midY)
        // Two points up: in the edge zone below the bars, short of the half row that would reveal a row by itself.
        let held = NSPoint(x: start.x, y: start.y - 2)

        sut.mouse(.leftMouseDown, at: start)
        let hold = sut.clock.registrationMark()
        sut.mouse(.leftMouseDragged, at: held)
        try await sut.clock.expectSleepers(1, after: hold)
        sut.clock.advance(by: GapDrag.slowestHold)
        let revealed = try #require(try await sut.applied.expectNext())
        sut.mouse(.leftMouseUp, at: held)
        try await sut.taskProvider.waitForAllTasks()

        #expect(revealed.above == 1)
    }
}

/// A single-file pane in a borderless window that is never ordered in, whose gutter's drags run through a
/// ``GapDragController`` that renders the file again with each expansion, as the window's model does.
@MainActor
private final class HeldFilePane {
    let clock = TestClock()
    let taskProvider = TaskProviderSpy.tolerant()
    /// Every expansion the controller revealed, in order.
    let applied = AsyncProbe<GapExpansion>()
    private let window: NSWindow
    private let host: NSHostingView<DiffTextView>
    private var expansions: [GapKey: GapExpansion] = [:]
    private var controller: GapDragController?

    /// The height of the tab bar over the pane.
    private let underBars: CGFloat

    init(underBars: CGFloat = 0) throws {
        self.underBars = underBars
        let rendered = try #require(Self.render([:]))
        host = NSHostingView(rootView: Self.pane(rendered, onGapDrag: nil, underBars: underBars))
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.borderless], backing: .buffered,
            defer: false)
        window.contentView = host
        controller = GapDragController(
            taskProvider: taskProvider, clock: clock,
            expansion: { [weak self] key in self?.expansions[key] ?? GapExpansion() },
            apply: { [weak self] expansion, key in self?.reveal(expansion, for: key) })
        host.rootView = Self.pane(rendered, onGapDrag: drag, underBars: underBars)
        settle()
    }

    /// Sixty lines changed at lines 10 and 40, with two lines of context: a gap between the two changes.
    private static func render(_ expansions: [GapKey: GapExpansion]) -> RenderedText? {
        let old = (1 ... 60).map { "let value\($0) = \($0)" }
        var new = old
        new[9] = "let value10 = ten"
        new[39] = "let value40 = forty"
        let diff = DiffRenderer.render(
            oldText: old.joined(separator: "\n") + "\n", newText: new.joined(separator: "\n") + "\n",
            language: .plain, layout: .changes(context: 2, expansions: expansions))
        return diff.unified
    }

    private static func pane(
        _ rendered: RenderedText, onGapDrag: ((GapDragEvent) -> Void)?, underBars: CGFloat
    ) -> DiffTextView {
        DiffTextView(
            rendered: rendered, gutter: .dual, keepsScrollPosition: true, wrapsLines: false, showsMinimap: false,
            onGapDrag: onGapDrag, underBars: underBars)
    }

    private var drag: (GapDragEvent) -> Void {
        { [weak self] event in self?.controller?.handle(event) }
    }

    /// Renders the file with `expansion` around `key`, as a drag step does, and shows it.
    private func reveal(_ expansion: GapExpansion, for key: GapKey) {
        expansions[key] = expansion
        guard let rendered = Self.render(expansions) else { return }
        host.rootView = Self.pane(rendered, onGapDrag: drag, underBars: underBars)
        settle()
        applied.send(expansion)
    }

    var gutter: DiffGutterView {
        subviews(of: DiffGutterView.self, in: host).first ?? DiffGutterView(clipView: nil)
    }

    /// How far the pane's text is scrolled down.
    var scrollOffset: CGFloat {
        (gutter.source as? TextKit2RowGeometry)?.textView.enclosingScrollView?.contentView.bounds.minY ?? 0
    }

    /// The gap between the two changes, with its band in the gutter.
    func middleGap() -> (marker: GapMarker, band: NSRect)? {
        var found: (GapMarker, NSRect)?
        gutter.forEachGap(in: gutter.bounds) { gap, band in
            if gap.hasSeparator { found = (gap.marker, band) }
        }
        return found
    }

    /// Scrolls the pane's text `delta` points further down.
    func scroll(by delta: CGFloat) {
        guard let clip = (gutter.source as? TextKit2RowGeometry)?.textView.enclosingScrollView?.contentView else {
            return
        }
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: clip.bounds.minY + delta))
        clip.enclosingScrollView?.reflectScrolledClipView(clip)
        settle()
    }

    /// Makes the pane `height` points tall.
    func fit(height: CGFloat) {
        window.setContentSize(NSSize(width: 600, height: height))
        settle()
    }

    func mouse(_ type: NSEvent.EventType, at point: NSPoint) {
        let gutter = gutter
        guard
            let event = NSEvent.mouseEvent(
                with: type, location: gutter.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
        else { return }
        switch type {
            case .leftMouseDown: gutter.mouseDown(with: event)
            case .leftMouseDragged: gutter.mouseDragged(with: event)
            default: gutter.mouseUp(with: event)
        }
    }

    private func settle() {
        for _ in 0 ..< 2 {
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
        }
    }
}

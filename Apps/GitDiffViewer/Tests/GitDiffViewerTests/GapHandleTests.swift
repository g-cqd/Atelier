import AppKit
import DiffCore
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// Where a gap row's handles sit, and what the gutter reports and draws for them (book DIFF-02).
@MainActor
struct GapHandleLayoutTests {
    @Test
    func `a gap between two changes stacks a grabber on each side of its hairline, each over its half of the row`() {
        let handles = GapHandleLayout.handles(
            [.extendsChangeAbove, .extendsChangeBelow], rowY: 100, rowHeight: 16, gutterWidth: 40)
        let hairline = GapHandleLayout.hairlineY(rowY: 100, rowHeight: 16)

        #expect(handles.map(\.handle) == [.extendsChangeAbove, .extendsChangeBelow])
        #expect(handles[0].grabber.maxY < hairline)
        #expect(handles[1].grabber.minY > hairline)
        #expect(handles[0].hitArea == CGRect(x: 0, y: 100, width: 40, height: 8))
        #expect(handles[1].hitArea == CGRect(x: 0, y: 108, width: 40, height: 8))
        #expect(handles.allSatisfy { $0.grabber.width == GapHandleLayout.grabberWidth && $0.grabber.midX == 20 })
    }

    @Test
    func `a gap at an end of the file centres one grabber of about 20 by 14 points on its hairline`() {
        let handles = GapHandleLayout.handles([.extendsChangeBelow], rowY: 0, rowHeight: 18, gutterWidth: 60)

        #expect(handles.count == 1)
        #expect(handles[0].grabber.size == CGSize(width: 20, height: 14))
        #expect(handles[0].grabber.midY == GapHandleLayout.hairlineY(rowY: 0, rowHeight: 18))
        #expect(handles[0].hitArea == CGRect(x: 0, y: 0, width: 60, height: 18))
    }

    @Test
    func `a narrow gutter narrows its grabbers to fit`() {
        let handles = GapHandleLayout.handles([.extendsChangeAbove], rowY: 0, rowHeight: 16, gutterWidth: 22)
        #expect(handles[0].grabber.minX >= 0)
        #expect(handles[0].grabber.maxX <= 22)
    }

    @Test
    func `the edge overshoot counts from the edge zone in the handle's direction only`() {
        let visible = CGRect(x: 0, y: 100, width: 40, height: 300)
        let zone = GapHandleLayout.edgeZone

        #expect(GapHandleLayout.edgeOvershoot(pointerY: 200, visible: visible, direction: 1) < 0)
        #expect(GapHandleLayout.edgeOvershoot(pointerY: 400 - zone + 4, visible: visible, direction: 1) == 4)
        #expect(GapHandleLayout.edgeOvershoot(pointerY: 430, visible: visible, direction: 1) == 30 + zone)
        #expect(GapHandleLayout.edgeOvershoot(pointerY: 430, visible: visible, direction: -1) < 0)
        #expect(GapHandleLayout.edgeOvershoot(pointerY: 100 + zone - 5, visible: visible, direction: -1) == 5)
    }
}

/// A gutter over an embedded text with a gap between two changes, in a scroll view of an offscreen window, and the
/// drag events it reports.
@MainActor
private final class GutterFixture {
    let gutter = DiffGutterView(clipView: nil)
    let scrollView: NSScrollView
    let window: NSWindow
    private(set) var events: [GapDragEvent] = []
    private var layout: StaticTextLayout

    /// Sixty lines changed at lines 10 and 40: a leading gap, a gap between the changes, and a trailing gap.
    init(visibleHeight: CGFloat = 1_000, expansions: [GapKey: GapExpansion] = [:]) throws {
        layout = try Self.layout(expansions: expansions)
        scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: visibleHeight))
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: visibleHeight), styleMask: [.borderless],
            backing: .buffered, defer: false)
        gutter.style = .new
        show(layout)
        scrollView.documentView = gutter
        window.contentView?.addSubview(scrollView)
        gutter.onGapDrag = { [weak self] event in self?.events.append(event) }
    }

    static func layout(expansions: [GapKey: GapExpansion]) throws -> StaticTextLayout {
        let old = (1 ... 60).map { "let value\($0) = \($0)" }
        var new = old
        new[9] = "let value10 = ten"
        new[39] = "let value40 = forty"
        let rendered = try #require(
            DiffRenderer.render(
                oldText: old.joined(separator: "\n") + "\n", newText: new.joined(separator: "\n") + "\n",
                language: .plain, layout: .changes(context: 2, expansions: expansions)
            )
            .new)
        let layout = StaticTextLayout(rendered: rendered)
        layout.layOut(mode: .none, viewportWidth: 800)
        return layout
    }

    /// Shows `layout`, as a re-render does.
    func show(_ layout: StaticTextLayout) {
        self.layout = layout
        gutter.source = layout
        gutter.rendered = layout.rendered
        gutter.frame = NSRect(x: 0, y: 0, width: gutter.thickness, height: layout.height)
    }

    /// The row of the gap between the two changes, in the gutter's coordinates.
    func middleGap() -> (marker: GapMarker, y: CGFloat, height: CGFloat)? {
        var found: (GapMarker, CGFloat, CGFloat)?
        gutter.forEachFragment(in: gutter.bounds) { fragment, row, _, y in
            guard let gap = row.gap, !gap.isLeading, !gap.isTrailing else { return }
            found = (gap, y, fragment.layoutFragmentFrame.height)
        }
        return found
    }

    func mouse(_ type: NSEvent.EventType, at point: NSPoint, clicks: Int = 1) {
        let location = gutter.convert(point, to: nil)
        guard
            let event = NSEvent.mouseEvent(
                with: type, location: location, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)
        else { return }
        switch type {
            case .leftMouseDown: gutter.mouseDown(with: event)
            case .leftMouseDragged: gutter.mouseDragged(with: event)
            case .leftMouseUp: gutter.mouseUp(with: event)
            default: gutter.mouseMoved(with: event)
        }
    }

    /// The gutter as it draws now, one sample per pixel of `rect`.
    func pixels(in rect: NSRect) -> [NSColor?] {
        guard let bitmap = gutter.bitmapImageRepForCachingDisplay(in: gutter.bounds) else { return [] }
        gutter.cacheDisplay(in: gutter.bounds, to: bitmap)
        let scale = CGFloat(bitmap.pixelsWide) / gutter.bounds.width
        var samples: [NSColor?] = []
        for y in Int(rect.minY * scale) ..< Int(rect.maxY * scale) {
            for x in Int(rect.minX * scale) ..< Int(rect.maxX * scale) { samples.append(bitmap.colorAt(x: x, y: y)) }
        }
        return samples
    }
}

@MainActor
struct DiffGutterGapHandleTests {
    @Test
    func `a press reports the handle under it, one for each half of a gap between two changes`() throws {
        let fixture = try GutterFixture()
        let gap = try #require(fixture.middleGap())
        let x = fixture.gutter.bounds.midX

        fixture.mouse(.leftMouseDown, at: NSPoint(x: x, y: gap.y + gap.height * 0.25))
        fixture.mouse(.leftMouseUp, at: NSPoint(x: x, y: gap.y + gap.height * 0.25))
        fixture.mouse(.leftMouseDown, at: NSPoint(x: x, y: gap.y + gap.height * 0.75))

        guard case .began(let upper, .extendsChangeAbove, _) = fixture.events.first,
            case .ended = fixture.events.dropFirst().first,
            case .began(let lower, .extendsChangeBelow, _) = fixture.events.last
        else {
            Issue.record("expected a press on each handle, got \(fixture.events)")
            return
        }
        #expect(upper == gap.marker)
        #expect(lower == gap.marker)
    }

    @Test
    func `a drag reports the pointer's travel from where it went down`() throws {
        let fixture = try GutterFixture()
        let gap = try #require(fixture.middleGap())
        let start = NSPoint(x: fixture.gutter.bounds.midX, y: gap.y + gap.height * 0.25)

        fixture.mouse(.leftMouseDown, at: start)
        fixture.mouse(.leftMouseDragged, at: NSPoint(x: start.x, y: start.y + 30))

        guard case .moved(let offset, let overshoot) = fixture.events.last else {
            Issue.record("expected a move, got \(fixture.events)")
            return
        }
        #expect(offset == 30)
        #expect(overshoot <= 0)
    }

    @Test
    func `a pointer held past the bottom of what shows reports how deep into the edge zone it is`() throws {
        let fixture = try GutterFixture(visibleHeight: 200)
        let gap = try #require(fixture.middleGap())
        fixture.gutter.scroll(NSPoint(x: 0, y: gap.y - 100))
        let visible = fixture.gutter.visibleRect
        let start = NSPoint(x: fixture.gutter.bounds.midX, y: gap.y + gap.height * 0.25)

        fixture.mouse(.leftMouseDown, at: start)
        fixture.mouse(.leftMouseDragged, at: NSPoint(x: start.x, y: visible.maxY + 10))

        guard case .moved(_, let overshoot) = fixture.events.last else {
            Issue.record("expected a move, got \(fixture.events)")
            return
        }
        #expect(overshoot == 10 + GapHandleLayout.edgeZone)
    }

    @Test
    func `a double click reveals the whole gap from the handle clicked`() throws {
        let fixture = try GutterFixture()
        let gap = try #require(fixture.middleGap())

        fixture.mouse(
            .leftMouseDown, at: NSPoint(x: fixture.gutter.bounds.midX, y: gap.y + gap.height * 0.75), clicks: 2)

        #expect(fixture.events == [.revealedAll(gap.marker, .extendsChangeBelow)])
    }

    @Test
    func `hovering one handle of a gap highlights that handle alone`() throws {
        let fixture = try GutterFixture()
        let gap = try #require(fixture.middleGap())
        let handles = GapHandleLayout.handles(
            gap.marker.handles, rowY: gap.y, rowHeight: gap.height, gutterWidth: fixture.gutter.bounds.width - 1)
        let upperBefore = fixture.pixels(in: handles[0].grabber)
        let lowerBefore = fixture.pixels(in: handles[1].grabber)

        fixture.mouse(.mouseMoved, at: NSPoint(x: fixture.gutter.bounds.midX, y: gap.y + gap.height * 0.25))

        #expect(fixture.pixels(in: handles[0].grabber) != upperBefore)
        #expect(fixture.pixels(in: handles[1].grabber) == lowerBefore)
    }

    @Test
    func `a handle held at the bottom edge keeps its gap in view as rows open above it`() throws {
        let fixture = try GutterFixture(visibleHeight: 200)
        let gap = try #require(fixture.middleGap())
        // The gap sits at the bottom of what shows, and its upper handle is held just past that edge.
        fixture.gutter.scroll(NSPoint(x: 0, y: gap.y + gap.height - 200))
        let start = NSPoint(x: fixture.gutter.bounds.midX, y: gap.y + gap.height * 0.25)
        fixture.mouse(.leftMouseDown, at: start)
        fixture.mouse(.leftMouseDragged, at: NSPoint(x: start.x, y: fixture.gutter.visibleRect.maxY + 4))

        // Five rows open above the gap, pushing it below what shows, as a hold does.
        fixture.show(try GutterFixture.layout(expansions: [gap.marker.key: GapExpansion(below: 5)]))
        fixture.gutter.layoutSubtreeIfNeeded()

        let moved = try #require(fixture.middleGap())
        #expect(moved.y > gap.y)
        #expect(fixture.gutter.visibleRect.contains(NSRect(x: 0, y: moved.y, width: 1, height: moved.height)))
    }
}

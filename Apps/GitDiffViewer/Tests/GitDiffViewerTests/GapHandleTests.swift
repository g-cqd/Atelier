import AppKit
import AtelierDiagnostics
import DiffCore
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// Where the halves of a gap's handle sit around its hairline (book DIFF-02).
@MainActor
struct GapHandleLayoutTests {
    private let key = GapKey(fileIndex: 0, gapIndex: 1)
    private let both: [GapHandle] = [.extendsChangeAbove, .extendsChangeBelow]

    @Test
    func `the halves of a gap between two changes make one rectangle centred on its hairline`() {
        let halves = GapHandleLayout.halves(both, boundaryY: 100, rowHeight: 15)

        #expect(halves.map(\.handle) == [.extendsChangeAbove, .extendsChangeBelow])
        #expect(halves[0].rect == CGRect(x: 2, y: 93, width: 18, height: 7))
        #expect(halves[1].rect == CGRect(x: 2, y: 100, width: 18, height: 7))
        #expect(halves[0].rect.union(halves[1].rect).midY == 100)
    }

    @Test
    func `a gap at the top of the file offers the lower half alone, hanging under its hairline`() {
        let marker = GapMarker(key: key, hiddenRows: 11, isLeading: true, isTrailing: false)
        let halves = GapHandleLayout.halves(marker.handles, boundaryY: 0, rowHeight: 15)

        #expect(halves.map(\.handle) == [.extendsChangeBelow])
        #expect(halves.first?.rect == CGRect(x: 2, y: 0, width: 18, height: 7))
    }

    @Test
    func `a gap at the end of a file offers the upper half alone, sitting on its hairline`() {
        let marker = GapMarker(key: key, hiddenRows: 9, isLeading: false, isTrailing: true)
        let halves = GapHandleLayout.halves(marker.handles, boundaryY: 300, rowHeight: 15)

        #expect(halves.map(\.handle) == [.extendsChangeAbove])
        #expect(halves.first?.rect == CGRect(x: 2, y: 293, width: 18, height: 7))
    }

    @Test
    func `a gap with no change on either side offers no half`() {
        let marker = GapMarker(key: key, hiddenRows: 40, isLeading: true, isTrailing: true)
        #expect(GapHandleLayout.halves(marker.handles, boundaryY: 0, rowHeight: 15).isEmpty)
    }

    @Test
    func `each half's hit area is its rectangle, a little taller on its rounded side only`() {
        let halves = GapHandleLayout.halves(both, boundaryY: 100, rowHeight: 15)
        let slop = GapHandleLayout.hitSlop

        #expect(halves[0].hitArea == CGRect(x: 2, y: 93 - slop, width: 18, height: 7 + slop))
        #expect(halves[1].hitArea == CGRect(x: 2, y: 100, width: 18, height: 7 + slop))
    }

    @Test
    func `the halves lie in the lane at the gutter's leading edge`() {
        let halves = GapHandleLayout.halves(both, boundaryY: 100, rowHeight: 15)
        #expect(halves.allSatisfy { $0.rect.minX > 0 && $0.hitArea.maxX < GapHandleLayout.laneWidth })
    }

    @Test
    func `rows too short for the rectangle shorten its halves, so a row between two gaps keeps them apart`() {
        let upper = GapHandleLayout.halves([.extendsChangeAbove], boundaryY: 111, rowHeight: 11)
        let lower = GapHandleLayout.halves([.extendsChangeBelow], boundaryY: 100, rowHeight: 11)

        #expect(upper.first?.rect.height == 5)
        #expect((lower.first?.rect.maxY ?? .infinity) < (upper.first?.rect.minY ?? 0))
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

/// What a gap's handle says in its tooltip, now that no row shows the lines it hides.
struct GapHandleHelpTests {
    private let key = GapKey(fileIndex: 0, gapIndex: 1)

    @Test
    func `a handle's help counts the lines its gap hides and tells how to reveal them`() {
        let marker = GapMarker(key: key, hiddenRows: 12, isLeading: false, isTrailing: false)
        #expect(marker.handleHelp == "12 hidden lines. Drag to reveal; double-click to reveal all")
    }

    @Test
    func `a handle's help counts a single hidden line in the singular`() {
        let marker = GapMarker(key: key, hiddenRows: 1, isLeading: false, isTrailing: false)
        #expect(marker.handleHelp == "1 hidden line. Drag to reveal; double-click to reveal all")
    }
}

/// A gutter over an embedded text with a gap between two changes, in a scroll view of an offscreen window, and the
/// drag events and diagnostic clicks it reports.
@MainActor
private final class GutterFixture {
    let gutter = DiffGutterView(clipView: nil)
    let scrollView: NSScrollView
    let window: NSWindow
    private(set) var events: [GapDragEvent] = []
    private(set) var diagnosticClicks: [Int] = []
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
        gutter.onDiagnosticClick = { [weak self] row, _, _, _ in self?.diagnosticClicks.append(row) }
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

    /// The gap between the two changes, the row its boundary lies above, and that boundary's y in the gutter: the top
    /// of that row as TextKit lays it out.
    func middleGap() -> (marker: GapMarker, row: Int, y: CGFloat)? {
        guard let gap = layout.rendered.gaps.first(where: { !$0.marker.isLeading && !$0.marker.isTrailing }) else {
            return nil
        }
        var top: CGFloat?
        gutter.forEachFragment(in: gutter.bounds) { _, _, row, y in
            if row == gap.boundary { top = y }
        }
        return top.map { (gap.marker, gap.boundary, $0) }
    }

    /// The halves of `gap` as the gutter lays them out.
    func halves(of gap: (marker: GapMarker, row: Int, y: CGFloat)) -> [GapHandleLayout.Half] {
        GapHandleLayout.halves(gap.marker.handles, boundaryY: gap.y, rowHeight: layout.rendered.lineHeight)
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
        let scale = window.backingScaleFactor
        var samples: [NSColor?] = []
        for y in Int(rect.minY * scale) ..< Int(rect.maxY * scale) {
            for x in Int(rect.minX * scale) ..< Int(rect.maxX * scale) { samples.append(bitmap.colorAt(x: x, y: y)) }
        }
        return samples
    }

    /// The gutter's pixel at `point`, as it draws now.
    func pixel(at point: NSPoint) -> NSColor? {
        guard let bitmap = gutter.bitmapImageRepForCachingDisplay(in: gutter.bounds) else { return nil }
        gutter.cacheDisplay(in: gutter.bounds, to: bitmap)
        // The window's scale, not the bitmap's width over the gutter's: a width short of whole pixels rounds up.
        let scale = window.backingScaleFactor
        return bitmap.colorAt(x: Int(point.x * scale), y: Int(point.y * scale))
    }
}

@MainActor
struct DiffGutterGapHandleTests {
    @Test(arguments: [GapHandle.extendsChangeAbove, .extendsChangeBelow])
    func `a press on a half of a gap between two changes reports that half's handle`(handle: GapHandle) throws {
        let fixture = try GutterFixture()
        let gap = try #require(fixture.middleGap())
        let half = try #require(fixture.halves(of: gap).first { $0.handle == handle })

        fixture.mouse(.leftMouseDown, at: NSPoint(x: half.rect.midX, y: half.rect.midY))

        guard case .began(let marker, let pressed, _) = fixture.events.first else {
            Issue.record("expected a press, got \(fixture.events)")
            return
        }
        #expect(marker == gap.marker)
        #expect(pressed == handle)
    }

    @Test
    func `a press on the rows' gutter outside the halves starts no drag`() throws {
        let fixture = try GutterFixture()
        let gap = try #require(fixture.middleGap())
        let upper = try #require(fixture.halves(of: gap).first)
        let width = fixture.gutter.bounds.width

        // Beside the halves on the hairline, and in the half's column but past its hit area.
        fixture.mouse(.leftMouseDown, at: NSPoint(x: width - 1.5, y: gap.y - 2))
        fixture.mouse(.leftMouseDown, at: NSPoint(x: width - 1.5, y: gap.y + 2))
        fixture.mouse(.leftMouseDown, at: NSPoint(x: upper.rect.midX, y: upper.hitArea.minY - 1))

        #expect(fixture.events.isEmpty)
    }

    @Test
    func `a line number beside a half keeps its diagnostic click`() throws {
        let fixture = try GutterFixture()
        let gap = try #require(fixture.middleGap())
        let finding = Finding(
            tool: .swiftlint, ruleID: "rule", message: "message", file: "a.swift", line: 1, column: nil,
            endLine: nil, endColumn: nil, severity: .warning)
        fixture.gutter.overlay = DiagnosticOverlay(rows: [
            gap.row - 1: DiagnosticOverlay.RowDiagnostics(
                severity: .warning, count: 1, findings: [finding], squiggles: [])
        ])
        let upper = try #require(fixture.halves(of: gap).first)

        fixture.mouse(.leftMouseDown, at: NSPoint(x: upper.rect.midX, y: upper.hitArea.minY - 1))
        fixture.mouse(.leftMouseDown, at: NSPoint(x: upper.rect.midX, y: upper.rect.midY))

        #expect(fixture.diagnosticClicks == [gap.row - 1])
        #expect(fixture.events.count == 1)
    }

    @Test
    func `a drag reports the pointer's travel from where it went down`() throws {
        let fixture = try GutterFixture()
        let gap = try #require(fixture.middleGap())
        let upper = try #require(fixture.halves(of: gap).first)
        let start = NSPoint(x: upper.rect.midX, y: upper.rect.midY)

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
        let upper = try #require(fixture.halves(of: gap).first)
        let start = NSPoint(x: upper.rect.midX, y: upper.rect.midY)

        fixture.mouse(.leftMouseDown, at: start)
        fixture.mouse(.leftMouseDragged, at: NSPoint(x: start.x, y: visible.maxY + 10))

        guard case .moved(_, let overshoot) = fixture.events.last else {
            Issue.record("expected a move, got \(fixture.events)")
            return
        }
        #expect(overshoot == 10 + GapHandleLayout.edgeZone)
    }

    @Test
    func `a double click reveals the whole gap from the half clicked`() throws {
        let fixture = try GutterFixture()
        let gap = try #require(fixture.middleGap())
        let lower = try #require(fixture.halves(of: gap).last)

        fixture.mouse(.leftMouseDown, at: NSPoint(x: lower.rect.midX, y: lower.rect.midY), clicks: 2)

        #expect(fixture.events == [.revealedAll(gap.marker, .extendsChangeBelow)])
    }

    @Test(arguments: [GapHandle.extendsChangeAbove, .extendsChangeBelow])
    func `hovering one half of a gap highlights that half alone`(handle: GapHandle) throws {
        let fixture = try GutterFixture()
        let gap = try #require(fixture.middleGap())
        let halves = fixture.halves(of: gap)
        let hovered = try #require(halves.first { $0.handle == handle })
        let other = try #require(halves.first { $0.handle != handle })
        let hoveredBefore = fixture.pixels(in: hovered.rect)
        let otherBefore = fixture.pixels(in: other.rect)

        fixture.mouse(.mouseMoved, at: NSPoint(x: hovered.rect.midX, y: hovered.rect.midY))

        #expect(fixture.pixels(in: hovered.rect) != hoveredBefore)
        #expect(fixture.pixels(in: other.rect) == otherBefore)
    }

    @Test
    func `the tooltip tells the hidden lines of the gap whose half is under the pointer`() throws {
        let fixture = try GutterFixture()
        let gap = try #require(fixture.middleGap())
        let lower = try #require(fixture.halves(of: gap).last)

        fixture.mouse(.mouseMoved, at: NSPoint(x: lower.rect.midX, y: lower.rect.midY))
        let over = fixture.gutter.toolTip
        fixture.mouse(.mouseMoved, at: NSPoint(x: fixture.gutter.bounds.width - 1.5, y: gap.y + 2))

        #expect(over == "\(gap.marker.hiddenRows) hidden lines. Drag to reveal; double-click to reveal all")
        #expect(fixture.gutter.toolTip == nil)
    }

    @Test
    func `the pointer on the rows' gutter outside the halves highlights neither`() throws {
        let fixture = try GutterFixture()
        let gap = try #require(fixture.middleGap())
        let halves = fixture.halves(of: gap)
        let before = halves.map { fixture.pixels(in: $0.rect) }

        fixture.mouse(.mouseMoved, at: NSPoint(x: fixture.gutter.bounds.width - 1.5, y: gap.y + 2))

        #expect(halves.map { fixture.pixels(in: $0.rect) } == before)
    }

    @Test
    func `line numbers start past the lane that holds the halves`() throws {
        let fixture = try GutterFixture()
        let gap = try #require(fixture.middleGap())
        let numbersLeft = fixture.gutter.numbersLeft

        #expect(fixture.halves(of: gap).allSatisfy { $0.hitArea.maxX < numbersLeft })
    }

    @Test
    func `a gutter widens by the handles' lane only while its text offers a handle`() throws {
        let fixture = try GutterFixture()
        let text = (1 ... 60).map { "let value\($0) = \($0)" }.joined(separator: "\n") + "\n"
        let rendered = try #require(DiffRenderer.render(oldText: text, newText: text, language: .plain).new)
        let whole = DiffGutterView(clipView: nil)
        whole.style = .new
        whole.rendered = rendered

        #expect(whole.numbersLeft < GapHandleLayout.laneWidth)
        #expect(fixture.gutter.thickness - whole.thickness == fixture.gutter.numbersLeft - whole.numbersLeft)
    }

    @Test
    func `the hairline crosses the gutter exactly on the boundary between the rows around the gap`() throws {
        let fixture = try GutterFixture()
        let gap = try #require(fixture.middleGap())
        // At the gutter's leading edge, clear of the halves and of the line numbers.
        let background = fixture.pixel(at: NSPoint(x: 0.5, y: gap.y - 5))

        #expect(fixture.pixel(at: NSPoint(x: 0.5, y: gap.y - 0.25)) != background)
        #expect(fixture.pixel(at: NSPoint(x: 0.5, y: gap.y + 0.25)) != background)
        #expect(fixture.pixel(at: NSPoint(x: 0.5, y: gap.y - 1.5)) == background)
        #expect(fixture.pixel(at: NSPoint(x: 0.5, y: gap.y + 1.5)) == background)
    }

    @Test
    func `a half held at the bottom edge keeps its gap's boundary in view as rows open above it`() throws {
        let fixture = try GutterFixture(visibleHeight: 200)
        let gap = try #require(fixture.middleGap())
        // The boundary sits at the bottom of what shows, and its upper half is held just past that edge.
        fixture.gutter.scroll(NSPoint(x: 0, y: gap.y + GapHandleLayout.halfHeight - 200))
        let upper = try #require(fixture.halves(of: gap).first)
        fixture.mouse(.leftMouseDown, at: NSPoint(x: upper.rect.midX, y: upper.rect.midY))
        fixture.mouse(
            .leftMouseDragged, at: NSPoint(x: upper.rect.midX, y: fixture.gutter.visibleRect.maxY + 4))

        // Five rows open above the boundary, pushing it below what shows, as a hold does.
        fixture.show(try GutterFixture.layout(expansions: [gap.marker.key: GapExpansion(below: 5)]))
        fixture.gutter.layoutSubtreeIfNeeded()

        let moved = try #require(fixture.middleGap())
        #expect(moved.y > gap.y)
        #expect(fixture.gutter.visibleRect.minY <= moved.y - GapHandleLayout.halfHeight)
        #expect(fixture.gutter.visibleRect.maxY >= moved.y + GapHandleLayout.halfHeight)
    }
}

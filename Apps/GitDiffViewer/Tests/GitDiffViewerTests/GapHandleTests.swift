import AppKit
import AtelierDiagnostics
import DiffCore
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// Where a gap's handle sits in its band, exactly one row tall (book DIFF-02): a small rectangle split by a separator
/// between two changes, and a lone half stuck to the band's edge at the top or the end of a file.
@MainActor
struct GapHandleLayoutTests {
    private let key = GapKey(fileIndex: 0, gapIndex: 1)
    private let both: [GapHandle] = [.extendsChangeAbove, .extendsChangeBelow]

    /// A band one row of `lineHeight` tall, at `y`, across a gutter 40 points wide less its separator.
    private func band(y: CGFloat = 0, lineHeight: CGFloat = 15) -> CGRect {
        CGRect(x: 0, y: y, width: 39, height: RenderedText.gapBandHeight(lineHeight: lineHeight))
    }

    @Test
    func `two halves sit above and below a separator across the band's middle, within the one row`() {
        let handle = GapHandleLayout.handle(both, in: band(y: 100))

        #expect(handle.halves.map(\.handle) == both)
        #expect(handle.separator == CGRect(x: 0, y: 107, width: 39, height: 1))
        #expect(handle.halves[0].rect == CGRect(x: 13, y: 101, width: 14, height: 6))
        #expect(handle.halves[1].rect == CGRect(x: 13, y: 108, width: 14, height: 6))
    }

    @Test(arguments: [13.0, 15, 18, 21])
    func `the halves fit in half a row each, whatever the line height`(lineHeight: CGFloat) throws {
        let band = band(lineHeight: lineHeight)
        let handle = GapHandleLayout.handle(both, in: band)
        let separator = try #require(handle.separator)

        #expect(handle.halves.allSatisfy { band.contains($0.rect) && $0.rect.height <= (lineHeight - 1) / 2 })
        #expect(handle.halves[0].rect.maxY == separator.minY)
        #expect(handle.halves[1].rect.minY == separator.maxY)
    }

    @Test
    func `a gap at the top of the file shows its lower half alone, flat against the band's top, with no separator`() {
        let marker = GapMarker(key: key, hiddenRows: 11, isLeading: true, isTrailing: false)
        let handle = GapHandleLayout.handle(marker.handles, in: band())

        #expect(handle.halves.map(\.handle) == [.extendsChangeBelow])
        #expect(handle.separator == nil)
        #expect(handle.halves.first?.rect == CGRect(x: 13, y: 0, width: 14, height: 6))
    }

    @Test
    func `a gap at the end of a file shows its upper half alone, flat against the band's bottom, with no separator`() {
        let marker = GapMarker(key: key, hiddenRows: 9, isLeading: false, isTrailing: true)
        let handle = GapHandleLayout.handle(marker.handles, in: band(y: 300))

        #expect(handle.halves.map(\.handle) == [.extendsChangeAbove])
        #expect(handle.separator == nil)
        #expect(handle.halves.first?.rect == CGRect(x: 13, y: 309, width: 14, height: 6))
    }

    @Test
    func `a gap with no change on either side offers no half`() {
        let marker = GapMarker(key: key, hiddenRows: 40, isLeading: true, isTrailing: true)
        #expect(GapHandleLayout.handle(marker.handles, in: band()).halves.isEmpty)
    }

    @Test
    func `each grip is 6 points long, centred across its half, 2 points from its flat side`() {
        let pair = GapHandleLayout.handle(both, in: band())
        let top = GapHandleLayout.handle([.extendsChangeBelow], in: band())
        let end = GapHandleLayout.handle([.extendsChangeAbove], in: band())

        #expect(pair.halves.map(\.grip.minY) == [4, 10])
        #expect(top.halves.map(\.grip.minY) == [2])
        #expect(end.halves.map(\.grip.minY) == [12])
        #expect((pair.halves + top.halves).allSatisfy { $0.grip.width == 6 && $0.grip.midX == $0.rect.midX })
    }

    @Test
    func `the handle is centred across the gutter on whole points, and narrowed to fit a narrow one`() {
        let wide = GapHandleLayout.handle(both, in: CGRect(x: 0, y: 0, width: 62.5, height: 15))
        let narrow = GapHandleLayout.handle(both, in: CGRect(x: 0, y: 0, width: 16, height: 15))

        #expect(wide.halves.allSatisfy { $0.rect.minX == 24 && $0.rect.width == 14 })
        #expect(narrow.halves.allSatisfy { $0.rect.minX >= 0 && $0.rect.maxX <= 16 && $0.rect.midX == 8 })
    }

    @Test
    func `each of two halves hits in its part of the band, across the gutter, split at the separator`() {
        let handle = GapHandleLayout.handle(both, in: band(y: 100))

        #expect(handle.halves[0].hitArea == CGRect(x: 0, y: 100, width: 39, height: 7.5))
        #expect(handle.halves[1].hitArea == CGRect(x: 0, y: 107.5, width: 39, height: 7.5))
    }

    @Test
    func `a lone half hits in its whole band`() {
        let handle = GapHandleLayout.handle([.extendsChangeAbove], in: band(y: 100))
        #expect(handle.halves.first?.hitArea == band(y: 100))
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
    /// The text the gutter numbers.
    var rendered: RenderedText { layout.rendered }

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

    /// A gap as the gutter shows it: its marker, the row its boundary lies above, and its band in the gutter.
    struct Gap {
        let marker: GapMarker
        let row: Int
        let band: NSRect
        /// Where its hairline crosses: the band's middle.
        var y: CGFloat { band.midY }
    }

    /// The gap between the two changes.
    func middleGap() -> Gap? {
        var found: Gap?
        gutter.forEachGap(in: gutter.bounds) { gap, band in
            guard !gap.marker.isLeading, !gap.marker.isTrailing else { return }
            found = Gap(marker: gap.marker, row: gap.boundary, band: band)
        }
        return found
    }

    /// The halves of `gap` as the gutter lays them out in its band.
    func halves(of gap: Gap) -> [GapHandleLayout.Half] {
        GapHandleLayout.handle(gap.marker.handles, in: gap.band).halves
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
    func `a press anywhere across a band's part grabs that part's half`() throws {
        let fixture = try GutterFixture()
        let gap = try #require(fixture.middleGap())

        fixture.mouse(.leftMouseDown, at: NSPoint(x: fixture.gutter.bounds.width - 2, y: gap.band.minY + 1))

        guard case .began(_, .extendsChangeAbove, _) = fixture.events.first else {
            Issue.record("expected a press on the upper half, got \(fixture.events)")
            return
        }
    }

    @Test
    func `a press in the rows around a band starts no drag`() throws {
        let fixture = try GutterFixture()
        let gap = try #require(fixture.middleGap())
        let middle = (fixture.gutter.bounds.width - 1) / 2

        fixture.mouse(.leftMouseDown, at: NSPoint(x: middle, y: gap.band.minY - 1))
        fixture.mouse(.leftMouseDown, at: NSPoint(x: middle, y: gap.band.maxY + 1))

        #expect(fixture.events.isEmpty)
    }

    @Test
    func `the row above a band keeps its line number's click`() throws {
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

        // On the number of the row above the band, then on the upper half in the band.
        let rowAbove = gap.band.minY - fixture.rendered.lineHeight / 2
        fixture.mouse(.leftMouseDown, at: NSPoint(x: fixture.gutter.bounds.width - 10, y: rowAbove))
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
        fixture.mouse(.mouseMoved, at: NSPoint(x: fixture.gutter.bounds.width - 1.5, y: gap.band.maxY + 2))

        #expect(over == "\(gap.marker.hiddenRows) hidden lines. Drag to reveal; double-click to reveal all")
        #expect(fixture.gutter.toolTip == nil)
    }

    @Test
    func `the pointer on the rows' gutter outside the halves highlights neither`() throws {
        let fixture = try GutterFixture()
        let gap = try #require(fixture.middleGap())
        let halves = fixture.halves(of: gap)
        let before = halves.map { fixture.pixels(in: $0.rect) }

        fixture.mouse(.mouseMoved, at: NSPoint(x: fixture.gutter.bounds.width - 1.5, y: gap.band.maxY + 2))

        #expect(halves.map { fixture.pixels(in: $0.rect) } == before)
    }

    @Test
    func `letting go of a half away from any half leaves neither highlighted`() throws {
        let fixture = try GutterFixture()
        let gap = try #require(fixture.middleGap())
        let halves = fixture.halves(of: gap)
        let before = halves.map { fixture.pixels(in: $0.rect) }
        let upper = try #require(halves.first)
        let start = NSPoint(x: upper.rect.midX, y: upper.rect.midY)
        let away = NSPoint(x: start.x, y: gap.band.maxY + 3 * fixture.rendered.lineHeight)

        fixture.mouse(.mouseMoved, at: start)
        fixture.mouse(.leftMouseDown, at: start)
        fixture.mouse(.leftMouseDragged, at: away)
        fixture.mouse(.leftMouseUp, at: away)

        #expect(halves.map { fixture.pixels(in: $0.rect) } == before)
    }

    @Test
    func `letting go of a half over the other highlights the other alone`() throws {
        let fixture = try GutterFixture()
        let gap = try #require(fixture.middleGap())
        let halves = fixture.halves(of: gap)
        let upper = try #require(halves.first)
        let lower = try #require(halves.last)
        let upperBefore = fixture.pixels(in: upper.rect)
        let lowerBefore = fixture.pixels(in: lower.rect)
        let start = NSPoint(x: upper.rect.midX, y: upper.rect.midY)
        let over = NSPoint(x: lower.rect.midX, y: lower.rect.midY)

        fixture.mouse(.mouseMoved, at: start)
        fixture.mouse(.leftMouseDown, at: start)
        fixture.mouse(.leftMouseDragged, at: over)
        fixture.mouse(.leftMouseUp, at: over)

        #expect(fixture.pixels(in: upper.rect) == upperBefore)
        #expect(fixture.pixels(in: lower.rect) != lowerBefore)
    }

    @Test
    func `a gutter keeps its width whether or not its text offers a handle`() throws {
        let fixture = try GutterFixture()
        let text = (1 ... 60).map { "let value\($0) = \($0)" }.joined(separator: "\n") + "\n"
        let rendered = try #require(DiffRenderer.render(oldText: text, newText: text, language: .plain).new)
        let whole = DiffGutterView(clipView: nil)
        whole.style = .new
        whole.rendered = rendered

        #expect(fixture.gutter.thickness == whole.thickness)
    }

    @Test
    func `the handle is centred across the gutter`() throws {
        let fixture = try GutterFixture()
        let gap = try #require(fixture.middleGap())
        let middle = (fixture.gutter.bounds.width - 1) / 2

        #expect(fixture.halves(of: gap).allSatisfy { abs($0.rect.midX - middle) <= 0.5 })
    }

    @Test
    func `the hairline crosses the gutter through the middle of its gap's band`() throws {
        let fixture = try GutterFixture()
        let gap = try #require(fixture.middleGap())
        #expect(gap.y == gap.band.midY)
        // At the gutter's leading edge, clear of the halves and of the line numbers.
        let background = fixture.pixel(at: NSPoint(x: 0.5, y: gap.y - 5))

        #expect(fixture.pixel(at: NSPoint(x: 0.5, y: gap.y - 0.25)) != background)
        #expect(fixture.pixel(at: NSPoint(x: 0.5, y: gap.y + 0.25)) != background)
        #expect(fixture.pixel(at: NSPoint(x: 0.5, y: gap.y - 1.5)) == background)
        #expect(fixture.pixel(at: NSPoint(x: 0.5, y: gap.y + 1.5)) == background)
    }

    @Test
    func `a half held at the bottom edge keeps its gap's band in view as rows open above it`() throws {
        let fixture = try GutterFixture(visibleHeight: 200)
        let gap = try #require(fixture.middleGap())
        // The band sits at the bottom of what shows, and its upper half is held just past that edge.
        fixture.gutter.scroll(NSPoint(x: 0, y: gap.band.maxY - 200))
        let upper = try #require(fixture.halves(of: gap).first)
        fixture.mouse(.leftMouseDown, at: NSPoint(x: upper.rect.midX, y: upper.rect.midY))
        fixture.mouse(
            .leftMouseDragged, at: NSPoint(x: upper.rect.midX, y: fixture.gutter.visibleRect.maxY + 4))

        // Five rows open above the boundary, pushing it below what shows, as a hold does.
        fixture.show(try GutterFixture.layout(expansions: [gap.marker.key: GapExpansion(below: 5)]))
        fixture.gutter.layoutSubtreeIfNeeded()

        let moved = try #require(fixture.middleGap())
        #expect(moved.band.minY > gap.band.minY)
        #expect(fixture.gutter.visibleRect.contains(moved.band))
    }
}

/// The gaps on the edges of a text and of its files: which boundaries the gutter finds there, and which halves it
/// draws on them.
@MainActor
struct DiffGutterGapEdgeTests {
    /// An embedded gutter over `rendered`, in an offscreen window, with the layout it reads, which it holds weakly.
    private func gutter(over rendered: RenderedText, style: GutterStyle) -> (DiffGutterView, StaticTextLayout, NSWindow)
    {
        let layout = StaticTextLayout(rendered: rendered)
        layout.layOut(mode: .none, viewportWidth: 800)
        let gutter = DiffGutterView(clipView: nil)
        gutter.style = style
        gutter.source = layout
        gutter.rendered = rendered
        gutter.frame = NSRect(x: 0, y: 0, width: gutter.thickness, height: layout.height)
        let window = NSWindow(
            contentRect: gutter.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView?.addSubview(gutter)
        return (gutter, layout, window)
    }

    /// The middle of the handles across `gutter`.
    private func handleMidX(in gutter: DiffGutterView) -> CGFloat {
        (gutter.bounds.width - 1) / 2
    }

    /// The gutter's pixels at `points`, as it draws now.
    private func pixels(of gutter: DiffGutterView, at points: [NSPoint]) -> [NSColor?] {
        guard let bitmap = gutter.bitmapImageRepForCachingDisplay(in: gutter.bounds) else { return [] }
        gutter.cacheDisplay(in: gutter.bounds, to: bitmap)
        let scale = gutter.window?.backingScaleFactor ?? 1
        return points.map { bitmap.colorAt(x: Int($0.x * scale), y: Int($0.y * scale)) }
    }

    /// Twenty lines changed at line 10, shown with a line of context: gaps above and below the one hunk.
    private func changedAtLineTen() -> (old: String, new: String) {
        let old = (1 ... 20).map { "let value\($0) = \($0)" }
        var new = old
        new[9] = "let value10 = ten"
        return (old.joined(separator: "\n") + "\n", new.joined(separator: "\n") + "\n")
    }

    @Test
    func `a gap at the top of the text has its band above the first row, one at the end below the last`() throws {
        let text = changedAtLineTen()
        let rendered = try #require(
            DiffRenderer.render(
                oldText: text.old, newText: text.new, language: .plain, layout: .changes(context: 1, expansions: [:])
            )
            .new)
        let (gutter, layout, _) = gutter(over: rendered, style: .new)
        defer { withExtendedLifetime(layout) {} }
        var bands: [Int: NSRect] = [:]
        var firstRowTop: CGFloat?

        gutter.forEachGap(in: gutter.bounds) { gap, band in bands[gap.boundary] = band }
        gutter.forEachFragment(in: gutter.bounds) { _, _, row, y in if row == 0 { firstRowTop = y } }

        let height = rendered.gapBandHeight
        let width = gutter.bounds.width - 1
        #expect(bands[0] == NSRect(x: 0, y: 0, width: width, height: height))
        #expect(firstRowTop == height)
        #expect(
            bands[rendered.rows.count] == NSRect(x: 0, y: gutter.bounds.maxY - height, width: width, height: height))
    }

    @Test
    func `the band at the top of the text shows its lower half against its top edge, and the end its upper half`()
        throws
    {
        let text = changedAtLineTen()
        let rendered = try #require(
            DiffRenderer.render(
                oldText: text.old, newText: text.new, language: .plain, layout: .changes(context: 1, expansions: [:])
            )
            .new)
        let (gutter, layout, _) = gutter(over: rendered, style: .new)
        defer { withExtendedLifetime(layout) {} }
        let x = handleMidX(in: gutter)
        let bottom = gutter.bounds.maxY

        // The gutter's background, then each half against the text's own edge, then the rest of each band.
        let samples = pixels(
            of: gutter,
            at: [
                NSPoint(x: 0.5, y: 40), NSPoint(x: x, y: 0.5), NSPoint(x: x, y: bottom - 0.5), NSPoint(x: x, y: 11),
                NSPoint(x: x, y: bottom - 11)
            ])

        #expect(samples.count == 5)
        #expect(samples[1] != samples[0])
        #expect(samples[2] != samples[0])
        #expect(samples[3] == samples[0])
        #expect(samples[4] == samples[0])
    }

    @Test
    func `the bands at the top and the end of the text carry no separator`() throws {
        let text = changedAtLineTen()
        let rendered = try #require(
            DiffRenderer.render(
                oldText: text.old, newText: text.new, language: .plain, layout: .changes(context: 1, expansions: [:])
            )
            .new)
        let (gutter, layout, _) = gutter(over: rendered, style: .new)
        defer { withExtendedLifetime(layout) {} }
        var bands: [NSRect] = []
        gutter.forEachGap(in: gutter.bounds) { _, band in bands.append(band) }
        try #require(bands.count == 2)

        // At the gutter's leading edge, clear of the halves, across each band's middle and away from it.
        let samples = pixels(
            of: gutter, at: bands.flatMap { [NSPoint(x: 0.5, y: $0.midY), NSPoint(x: 0.5, y: $0.minY + 2)] })

        #expect(samples.count == 4)
        #expect(samples[0] == samples[1])
        #expect(samples[2] == samples[3])
    }

    @Test
    func `a gap draws only the halves it offers, as on either side of a file's header`() throws {
        let text = changedAtLineTen()
        let files = ["a.txt", "b.txt"]
            .map {
                FileDiffInput(title: $0, oldText: text.old, newText: text.new, language: .plain)
            }
        let rendered = try #require(DiffRenderer.renderCombined(files: files, context: 1, expansions: [:]).unified)
        let (gutter, layout, _) = gutter(over: rendered, style: .dual)
        defer { withExtendedLifetime(layout) {} }
        // The bands on either side of the second file's header: the first file's trailing gap above it, which offers
        // its upper half alone, and the second file's leading gap below it, which offers its lower half alone.
        let header = try #require(rendered.rows.indices.dropFirst().first { rendered.rows[$0].kind == .header })
        var bands: [Int: NSRect] = [:]
        gutter.forEachGap(in: gutter.bounds) { gap, band in bands[gap.boundary] = band }
        let above = try #require(bands[header])
        let below = try #require(bands[header + 1])
        let x = handleMidX(in: gutter)

        // The background, clear of the bands; each band's part toward the header, where a second half and a
        // separator would lie; then each band's offered half, against the band's edge away from the header.
        let samples = pixels(
            of: gutter,
            at: [
                NSPoint(x: 0.5, y: above.maxY + 3), NSPoint(x: x, y: above.minY + 3), NSPoint(x: x, y: below.maxY - 3),
                NSPoint(x: 0.5, y: above.midY), NSPoint(x: 0.5, y: below.midY), NSPoint(x: x, y: above.maxY - 1.5),
                NSPoint(x: x, y: below.minY + 1.5)
            ])

        #expect(samples.count == 7)
        #expect(samples[1 ... 4].allSatisfy { $0 == samples[0] })
        #expect(samples[5] != samples[0])
        #expect(samples[6] != samples[0])
    }
}

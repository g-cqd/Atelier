import AppKit
import DiffCore
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// Where the compact inline view's markers sit (book DIFF-04; `compact-inline-design.md`).
struct ChangeMarkerLayoutTests {
    @Test
    func `a bar lies in the gutter's leading padding, a point wider under the pointer`() {
        let bar = ChangeMarkerLayout.bar(top: 30, bottom: 60, isHovered: false)
        let hovered = ChangeMarkerLayout.bar(top: 30, bottom: 60, isHovered: true)

        #expect(bar == CGRect(x: 2, y: 30, width: 3, height: 30))
        #expect(hovered.width == bar.width + 1)
        #expect(hovered.maxX <= ChangeMarkerLayout.hitWidth)
    }

    @Test
    func `a wedge sits across its boundary, or inside the row beside it`() {
        #expect(ChangeMarkerLayout.wedge(at: 40, placement: .centred).midY == 40)
        #expect(ChangeMarkerLayout.wedge(at: 40, placement: .below).minY == 40)
        #expect(ChangeMarkerLayout.wedge(at: 40, placement: .above).maxY == 40)
    }
}

/// The compact inline view's markers in a gutter over an embedded text: where they sit on the rows, and what the pointer
/// does with them (book DIFF-04).
@MainActor
struct DiffGutterChangeMarkerTests {
    /// Thirty lines: line 5 modified and line 12 removed.
    private static func layout(context: Int = 2) -> StaticTextLayout? {
        let old = (1 ... 30).map { "let value\($0) = \($0)" }
        var new = old
        new[4] = "let value5 = five"
        new.remove(at: 11)
        let prepared = PreparedDiff(
            FileDiffInput(
                title: "", oldText: old.joined(separator: "\n") + "\n", newText: new.joined(separator: "\n") + "\n",
                language: .plain), granularity: .word)
        let diff = DiffRenderer.render(
            prepared: [prepared], options: DiffRenderer.Options(sides: [.unified], compactsInline: true),
            layout: .changes(context: context, expansions: [:]), withHeaders: false)
        guard let unified = diff.unified else { return nil }
        let layout = StaticTextLayout(rendered: unified)
        layout.layOut(mode: .none, viewportWidth: 800)
        return layout
    }

    /// A gutter over `layout`, in a scroll view of a window that is never ordered in, and the changes it reports.
    @MainActor
    private final class Fixture {
        let gutter = DiffGutterView(clipView: nil)
        let window: NSWindow
        let layout: StaticTextLayout
        private(set) var toggled: [ChangeKey] = []

        init(_ layout: StaticTextLayout) {
            self.layout = layout
            let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 800))
            window = NSWindow(
                contentRect: scrollView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            gutter.style = .dual
            gutter.source = layout
            gutter.rendered = layout.rendered
            gutter.frame = NSRect(x: 0, y: 0, width: gutter.thickness, height: layout.height)
            scrollView.documentView = gutter
            window.contentView?.addSubview(scrollView)
            gutter.onChangeToggle = { [weak self] key in self?.toggled.append(key) }
        }

        /// Each marker in the gutter, with its change.
        func markers() -> [(change: RenderedChange, shape: ChangeMarkerLayout.Shape)] {
            var markers: [(change: RenderedChange, shape: ChangeMarkerLayout.Shape)] = []
            gutter.forEachChangeMarker(in: gutter.bounds) { markers.append((change: $0, shape: $1)) }
            return markers
        }

        /// The top of each row in the gutter.
        func rowTops() -> [Int: CGFloat] {
            var tops: [Int: CGFloat] = [:]
            gutter.forEachFragment(in: gutter.bounds) { _, _, row, y in tops[row] = y }
            return tops
        }

        func mouse(_ type: NSEvent.EventType, at point: NSPoint) {
            guard
                let event = NSEvent.mouseEvent(
                    with: type, location: gutter.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
            else { return }
            if type == .leftMouseDown { gutter.mouseDown(with: event) } else { gutter.mouseMoved(with: event) }
        }

        /// The gutter's pixels in `rect`, as it draws now.
        func pixels(in rect: NSRect) -> Data? {
            guard let bitmap = gutter.bitmapImageRepForCachingDisplay(in: gutter.bounds) else { return nil }
            gutter.cacheDisplay(in: gutter.bounds, to: bitmap)
            let scale = window.backingScaleFactor
            let crop = NSRect(
                x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
            return bitmap.cgImage?.cropping(to: crop).flatMap { NSBitmapImageRep(cgImage: $0).tiffRepresentation }
        }
    }

    @Test
    func `a folded change's bar runs from its first row's top to its last row's bottom`() throws {
        let fixture = Fixture(try #require(Self.layout()))
        let tops = fixture.rowTops()
        let (change, shape) = try #require(fixture.markers().first { $0.change.kind == .modified })
        guard case .bar(let bar) = shape else {
            Issue.record("expected a bar, got \(shape)")
            return
        }
        let first = try #require(tops[change.rows.lowerBound])

        #expect(bar.minY == first)
        #expect(bar.height == fixture.layout.rendered.lineHeight * CGFloat(change.rows.count))
    }

    @Test(arguments: [2, 0])
    func `a folded removal's wedge marks its boundary, below it under a band`(context: Int) throws {
        let fixture = Fixture(try #require(Self.layout(context: context)))
        let tops = fixture.rowTops()
        let (change, shape) = try #require(fixture.markers().first { $0.change.kind == .removed })
        guard case .wedge(let wedge) = shape else {
            Issue.record("expected a wedge, got \(shape)")
            return
        }
        let boundary = try #require(tops[change.rows.lowerBound])

        // With no context, the gap before the removal's row lies on its boundary, and its band above it.
        #expect(context == 0 ? wedge.minY == boundary : wedge.midY == boundary)
    }

    @Test
    func `a press on a marker reports its change`() throws {
        let fixture = Fixture(try #require(Self.layout()))
        let markers = fixture.markers()

        for (_, shape) in markers { fixture.mouse(.leftMouseDown, at: NSPoint(x: 3, y: shape.rect.midY)) }

        #expect(fixture.toggled == markers.map { $0.change.key })
    }

    @Test
    func `a press on a line number beside a marker reports no change`() throws {
        let fixture = Fixture(try #require(Self.layout()))
        let bar = try #require(fixture.markers().first).shape.rect

        fixture.mouse(.leftMouseDown, at: NSPoint(x: fixture.gutter.bounds.width - 4, y: bar.midY))

        #expect(fixture.toggled.isEmpty)
    }

    @Test
    func `hovering a marker draws it stronger and tells its change in the tooltip`() throws {
        let fixture = Fixture(try #require(Self.layout()))
        let (change, shape) = try #require(fixture.markers().first)
        let area = NSRect(x: 0, y: shape.rect.minY, width: ChangeMarkerLayout.hitWidth, height: shape.rect.height)
        let before = fixture.pixels(in: area)

        fixture.mouse(.mouseMoved, at: NSPoint(x: 3, y: shape.rect.midY))

        #expect(fixture.pixels(in: area) != before)
        #expect(fixture.gutter.toolTip == change.help)
    }
}

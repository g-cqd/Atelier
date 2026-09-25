import DiffCore
import Foundation
import Testing

@testable import DiffComparison
@testable import DiffRendering

/// The arithmetic of a gap handle's drag: direction, clamping, the two sides of a gap, and the edge-hold rate
/// (book DIFF-02).
struct GapDragTests {
    /// A gap between two changes hiding `hidden` rows.
    private func between(hiding hidden: Int = 20) -> GapMarker {
        GapMarker(key: GapKey(fileIndex: 0, gapIndex: 1), hiddenRows: hidden, isLeading: false, isTrailing: false)
    }

    private func drag(_ handle: GapHandle, hiding hidden: Int = 20, from base: GapExpansion = GapExpansion())
        -> GapDrag
    {
        GapDrag(marker: between(hiding: hidden), handle: handle, base: base, lineHeight: 10)
    }

    @Test
    func `travel along the handle's direction reveals a row per row height`() {
        var sut = drag(.extendsChangeAbove)
        sut.move(offset: 34, edgeOvershoot: 0)
        #expect(sut.expansion == GapExpansion(below: 3, above: 0))
    }

    @Test
    func `travel against the handle's direction reveals nothing`() {
        var sut = drag(.extendsChangeAbove, from: GapExpansion(below: 2, above: 1))
        sut.move(offset: -80, edgeOvershoot: 0)
        #expect(sut.expansion == GapExpansion(below: 2, above: 1))
    }

    @Test
    func `dragging back hides revealed rows down to where the drag began and no further`() {
        var sut = drag(.extendsChangeBelow)
        sut.move(offset: -60, edgeOvershoot: 0)
        #expect(sut.expansion == GapExpansion(below: 0, above: 6))
        sut.move(offset: -20, edgeOvershoot: 0)
        #expect(sut.expansion == GapExpansion(below: 0, above: 2))
        sut.move(offset: 40, edgeOvershoot: 0)
        #expect(sut.expansion == GapExpansion())
    }

    @Test
    func `a drag reveals at most the rows the gap hides`() {
        var sut = drag(.extendsChangeAbove, hiding: 5)
        sut.move(offset: 2_000, edgeOvershoot: 0)
        #expect(sut.revealed == 5)
    }

    @Test
    func `each handle of a gap between two changes grows its own change`() {
        var upper = drag(.extendsChangeAbove)
        var lower = drag(.extendsChangeBelow)
        upper.move(offset: 30, edgeOvershoot: 0)
        lower.move(offset: -30, edgeOvershoot: 0)
        #expect(upper.expansion == GapExpansion(below: 3, above: 0))
        #expect(lower.expansion == GapExpansion(below: 0, above: 3))
    }

    @Test
    func `a gap between two changes offers a handle for each, and a gap at an end of the file one`() {
        let key = GapKey(fileIndex: 0, gapIndex: 0)
        #expect(between().handles == [.extendsChangeAbove, .extendsChangeBelow])
        #expect(
            GapMarker(key: key, hiddenRows: 4, isLeading: true, isTrailing: false).handles == [.extendsChangeBelow])
        #expect(
            GapMarker(key: key, hiddenRows: 4, isLeading: false, isTrailing: true).handles == [.extendsChangeAbove])
        #expect(GapMarker(key: key, hiddenRows: 4, isLeading: true, isTrailing: true).handles.isEmpty)
    }

    @Test
    func `a pointer clear of the edge zone never holds`() {
        #expect(GapDrag.holdInterval(overshoot: 0) == nil)
        #expect(GapDrag.holdInterval(overshoot: -12) == nil)
    }

    @Test
    func `the hold rate rises with the depth into the edge zone and stays bounded`() throws {
        let atStart = try #require(GapDrag.holdInterval(overshoot: 0.5))
        let halfway = try #require(GapDrag.holdInterval(overshoot: GapDrag.rampDepth / 2))
        #expect(atStart <= GapDrag.slowestHold)
        #expect(atStart > halfway)
        #expect(halfway > GapDrag.fastestHold)
        #expect(GapDrag.holdInterval(overshoot: GapDrag.rampDepth) == GapDrag.fastestHold)
        #expect(GapDrag.holdInterval(overshoot: 10_000) == GapDrag.fastestHold)
        // Not too fast: never more than twenty rows a second.
        #expect(GapDrag.fastestHold >= .milliseconds(50))
    }

    @Test
    func `holding reveals one row per step until the gap is open`() {
        var sut = drag(.extendsChangeAbove, hiding: 3)
        sut.move(offset: 10, edgeOvershoot: 5)
        #expect(sut.holdInterval != nil)
        for _ in 0 ..< 5 { sut.hold() }
        #expect(sut.revealed == 3)
        #expect(sut.holdInterval == nil)
    }

    @Test
    func `rows revealed by holding go again when the pointer comes back`() {
        var sut = drag(.extendsChangeAbove)
        sut.move(offset: 20, edgeOvershoot: 5)
        sut.hold()
        sut.hold()
        #expect(sut.revealed == 4)
        sut.move(offset: -20, edgeOvershoot: 0)
        #expect(sut.revealed == 0)
    }

    /// A handle pressed in the edge zone and pulled back against its direction stays in the zone: it holds nothing.
    @Test
    func `a pointer in the edge zone behind where the drag began reveals nothing`() {
        var sut = drag(.extendsChangeAbove)
        sut.move(offset: -3, edgeOvershoot: 5)
        #expect(sut.holdInterval == nil)
        sut.hold()
        #expect(sut.revealed == 0)
    }

    @Test
    func `coming back behind where the drag began hides the rows a hold revealed`() {
        var sut = drag(.extendsChangeBelow)
        sut.move(offset: -10, edgeOvershoot: 5)
        for _ in 0 ..< 5 { sut.hold() }
        #expect(sut.revealed == 6)
        sut.move(offset: 4, edgeOvershoot: 0)
        #expect(sut.expansion == GapExpansion())
    }

    @Test
    func `revealing all opens the whole gap from the handle's side`() {
        var sut = drag(.extendsChangeBelow, hiding: 12, from: GapExpansion(below: 2, above: 0))
        sut.revealAll()
        #expect(sut.expansion == GapExpansion(below: 2, above: 12))
    }
}

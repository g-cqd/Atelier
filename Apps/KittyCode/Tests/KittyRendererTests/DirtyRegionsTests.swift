import Testing

@testable import KittyRenderer

@Suite struct DirtyRegionsTests {
    @Test func `empty regions report isEmpty`() {
        let sut = DirtyRegions()
        #expect(sut.isEmpty)
        #expect(sut.rectangles.isEmpty)
    }

    @Test func `marking a rect makes it non-empty`() {
        var sut = DirtyRegions()
        sut.mark(DirtyRect(row: 0, col: 0, height: 1, width: 10))
        #expect(!sut.isEmpty)
        #expect(sut.rectangles.count == 1)
    }

    @Test func `contains returns true for cells inside a marked rect`() {
        var sut = DirtyRegions()
        sut.mark(DirtyRect(row: 5, col: 10, height: 3, width: 20))
        #expect(sut.contains(row: 5, col: 10))
        #expect(sut.contains(row: 7, col: 29))
        #expect(sut.contains(row: 6, col: 15))
    }

    @Test func `contains returns false for cells outside any marked rect`() {
        var sut = DirtyRegions()
        sut.mark(DirtyRect(row: 5, col: 10, height: 3, width: 20))
        #expect(!sut.contains(row: 4, col: 10))  // row before
        #expect(!sut.contains(row: 8, col: 10))  // row after (height=3 → maxRow=8 exclusive)
        #expect(!sut.contains(row: 5, col: 9))  // col before
        #expect(!sut.contains(row: 5, col: 30))  // col after
    }

    @Test func `union of multiple rects is contained`() {
        var sut = DirtyRegions()
        sut.mark(DirtyRect(row: 0, col: 0, height: 1, width: 5))
        sut.mark(DirtyRect(row: 10, col: 5, height: 2, width: 3))
        #expect(sut.contains(row: 0, col: 0))
        #expect(sut.contains(row: 0, col: 4))
        #expect(sut.contains(row: 10, col: 5))
        #expect(sut.contains(row: 11, col: 7))
        #expect(!sut.contains(row: 5, col: 5))  // gap between rects
    }

    @Test func `clear removes all rects`() {
        var sut = DirtyRegions()
        sut.mark(DirtyRect(row: 0, col: 0, height: 5, width: 5))
        sut.mark(DirtyRect(row: 10, col: 0, height: 5, width: 5))
        sut.clear()
        #expect(sut.isEmpty)
        #expect(!sut.contains(row: 0, col: 0))
    }

    @Test func `markAll covers the whole buffer`() {
        var sut = DirtyRegions()
        sut.markAll(columns: 80, rows: 24)
        #expect(!sut.isEmpty)
        #expect(sut.contains(row: 0, col: 0))
        #expect(sut.contains(row: 23, col: 79))
        #expect(!sut.contains(row: 24, col: 0))  // out of bounds row
        #expect(!sut.contains(row: 0, col: 80))  // out of bounds col
    }

    @Test func `formUnion merges another DirtyRegions in place`() {
        var lhs = DirtyRegions()
        lhs.mark(DirtyRect(row: 0, col: 0, height: 2, width: 2))
        var rhs = DirtyRegions()
        rhs.mark(DirtyRect(row: 5, col: 5, height: 2, width: 2))
        lhs.formUnion(rhs)
        #expect(lhs.contains(row: 0, col: 0))
        #expect(lhs.contains(row: 5, col: 5))
        #expect(lhs.rectangles.count == 2)
    }

    @Test func `marking a zero-size rect is a no-op`() {
        var sut = DirtyRegions()
        sut.mark(DirtyRect(row: 0, col: 0, height: 0, width: 5))
        sut.mark(DirtyRect(row: 0, col: 0, height: 5, width: 0))
        #expect(sut.isEmpty)
    }

    @Test func `markRow is a convenience for a single-row rect`() {
        var sut = DirtyRegions()
        sut.markRow(7, columns: 80)
        #expect(sut.contains(row: 7, col: 0))
        #expect(sut.contains(row: 7, col: 79))
        #expect(!sut.contains(row: 6, col: 0))
        #expect(!sut.contains(row: 8, col: 0))
    }
}

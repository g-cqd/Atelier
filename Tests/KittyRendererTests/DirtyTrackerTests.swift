import Testing

@testable import KittyCodecs
@testable import KittyRenderer
@testable import KittyTerminal

@Suite
struct DirtyTrackerTests {
    @Test
    func `Mark and check dirty`() {
        var tracker = DirtyTracker(capacity: 100)
        #expect(!tracker.isDirty(5))
        tracker.mark(5)
        #expect(tracker.isDirty(5))
        #expect(!tracker.isDirty(4))
    }

    @Test
    func `Out of bounds indices are ignored`() {
        var tracker = DirtyTracker(capacity: 10)

        tracker.mark(-1)
        tracker.mark(10)

        #expect(!tracker.isDirty(-1))
        #expect(!tracker.isDirty(10))
        #expect(tracker.isEmpty)
    }

    @Test
    func `Clear resets all bits`() {
        var tracker = DirtyTracker(capacity: 100)
        tracker.mark(0)
        tracker.mark(99)
        tracker.clear()
        #expect(tracker.isEmpty)
    }

    @Test
    func `Dirty ranges`() {
        var tracker = DirtyTracker(capacity: 30)  // 10 cols × 3 rows
        tracker.mark(10)  // row 1, col 0
        tracker.mark(11)  // row 1, col 1
        tracker.mark(12)  // row 1, col 2
        let ranges = tracker.dirtyRanges(columns: 10)
        #expect(ranges.count == 1)
        #expect(ranges[0].row == 1)
        #expect(ranges[0].colStart == 0)
        #expect(ranges[0].colEnd == 3)
    }
}

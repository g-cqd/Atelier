import Foundation
import Testing

@testable import KittyText

@Suite struct TextSelectionTests {
    @Test func `isCollapsed when anchor equals head`() {
        let pos = TextPosition(row: 2, col: 4)
        let sel = TextSelection(anchor: pos, head: pos)
        #expect(sel.isCollapsed)
    }

    @Test func `isCollapsed is false when anchor differs from head`() {
        let sel = TextSelection(
            anchor: TextPosition(row: 0, col: 0),
            head: TextPosition(row: 0, col: 5)
        )
        #expect(!sel.isCollapsed)
    }

    @Test func `ordered returns anchor first when anchor is before head`() {
        let anchor = TextPosition(row: 1, col: 2)
        let head = TextPosition(row: 3, col: 0)
        let sel = TextSelection(anchor: anchor, head: head)
        let (start, end) = sel.ordered
        #expect(start == anchor)
        #expect(end == head)
    }

    @Test func `ordered returns head first when head is before anchor`() {
        let anchor = TextPosition(row: 5, col: 0)
        let head = TextPosition(row: 2, col: 8)
        let sel = TextSelection(anchor: anchor, head: head)
        let (start, end) = sel.ordered
        #expect(start == head)
        #expect(end == anchor)
    }

    @Test func `TextPosition comparison is row-major`() {
        let earlier = TextPosition(row: 1, col: 99)
        let later = TextPosition(row: 2, col: 0)
        #expect(earlier < later)
    }

    @Test func `TextPosition comparison uses col when rows are equal`() {
        let left = TextPosition(row: 3, col: 4)
        let right = TextPosition(row: 3, col: 10)
        #expect(left < right)
    }
}

import Testing

@testable import KittyCodecs
@testable import KittyRenderer
@testable import KittySyntax
@testable import KittyWidgets

@Suite
struct RectTests {
    @Test func `zero has all zero components`() {
        let rect = Rect.zero

        #expect(rect.x == 0)
        #expect(rect.y == 0)
        #expect(rect.width == 0)
        #expect(rect.height == 0)
    }

    @Test func `zero is empty`() {
        #expect(Rect.zero.isEmpty)
    }

    @Test func `rect with positive dimensions is not empty`() {
        let rect = Rect(x: 0, y: 0, width: 10, height: 5)
        #expect(!rect.isEmpty)
    }

    @Test func `rect with zero width is empty`() {
        let rect = Rect(x: 0, y: 0, width: 0, height: 5)
        #expect(rect.isEmpty)
    }

    @Test func `rect with zero height is empty`() {
        let rect = Rect(x: 0, y: 0, width: 10, height: 0)
        #expect(rect.isEmpty)
    }

    @Test func `equality holds for identical rects`() {
        let a = Rect(x: 1, y: 2, width: 3, height: 4)
        let b = Rect(x: 1, y: 2, width: 3, height: 4)
        #expect(a == b)
    }

    static let differentRects: [Rect] = [
        Rect(x: 9, y: 2, width: 3, height: 4),
        Rect(x: 1, y: 9, width: 3, height: 4),
        Rect(x: 1, y: 2, width: 9, height: 4),
        Rect(x: 1, y: 2, width: 3, height: 9),
    ]

    @Test(arguments: differentRects)
    func `equality fails when any component differs`(different: Rect) {
        let base = Rect(x: 1, y: 2, width: 3, height: 4)
        #expect(base != different)
    }

    @Test func `maxX equals x plus width`() {
        let rect = Rect(x: 5, y: 0, width: 10, height: 1)
        #expect(rect.maxX == 15)
    }

    @Test func `maxY equals y plus height`() {
        let rect = Rect(x: 0, y: 3, width: 1, height: 7)
        #expect(rect.maxY == 10)
    }
}

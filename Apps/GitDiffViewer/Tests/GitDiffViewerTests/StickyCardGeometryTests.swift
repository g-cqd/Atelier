import CoreGraphics
import Testing

@testable import DiffTextKit

struct StickyCardGeometryTests {
    private let size = CGSize(width: 400, height: 300)
    private let headerHeight: CGFloat = 30

    private func makeSUT(pinY: CGFloat, size: CGSize? = nil, headerHeight: CGFloat? = nil) -> StickyCardGeometry {
        StickyCardGeometry(pinY: pinY, size: size ?? self.size, headerHeight: headerHeight ?? self.headerHeight)
    }

    @Test(arguments: [-120, -0.5, 0, -CGFloat.infinity] as [CGFloat])
    func `a card whose top has not reached the pin line rests with its whole outline`(pinY: CGFloat) {
        let sut = makeSUT(pinY: pinY)
        #expect(sut.offset == 0)
        #expect(sut.clipFrame == CGRect(origin: .zero, size: size))
        #expect(sut.bodyOrigin == .zero)
        #expect(!sut.isPinned)
    }

    @Test
    func `past the pin line the visible card starts at the line and the body holds still on the card`() {
        let sut = makeSUT(pinY: 50)
        #expect(sut.offset == 50)
        #expect(sut.clipFrame == CGRect(x: 0, y: 50, width: 400, height: 250))
        #expect(sut.bodyOrigin == CGPoint(x: 0, y: -50))
        #expect(sut.isPinned)
    }

    @Test(arguments: [(269.5, 269.5), (270, 270), (270.5, 270), (5000, 270), (.infinity, 270)] as [(CGFloat, CGFloat)])
    func `the card's bottom pushes the header out once only the header is left`(pinY: CGFloat, offset: CGFloat) {
        let sut = makeSUT(pinY: pinY)
        #expect(sut.offset == offset)
        #expect(sut.clipFrame.maxY == size.height)
        #expect(sut.clipFrame.height >= headerHeight)
    }

    @Test(arguments: [0, 10, 1000] as [CGFloat])
    func `a folded card, only a header tall, never leaves its place`(pinY: CGFloat) {
        let sut = makeSUT(pinY: pinY, size: CGSize(width: 400, height: headerHeight))
        #expect(sut.offset == 0)
        #expect(!sut.isPinned)
    }

    @Test
    func `a header taller than its card keeps the card at rest`() {
        let sut = makeSUT(pinY: 40, size: CGSize(width: 400, height: 20))
        #expect(sut.offset == 0)
        #expect(sut.clipFrame == CGRect(x: 0, y: 0, width: 400, height: 20))
    }

    @Test
    func `a NaN pin line keeps the card at rest`() {
        let sut = makeSUT(pinY: .nan)
        #expect(sut.offset == 0)
        #expect(sut.clipFrame == CGRect(origin: .zero, size: size))
    }

    @Test(arguments: [-5, .nan, .infinity] as [CGFloat])
    func `a malformed card height counts as empty`(height: CGFloat) {
        let sut = makeSUT(pinY: 50, size: CGSize(width: 400, height: height))
        #expect(sut.offset == 0)
        #expect(sut.clipFrame.height == 0)
    }

    @Test
    func `a negative header height counts as no header`() {
        let sut = makeSUT(pinY: 500, headerHeight: -10)
        #expect(sut.offset == 300)
        #expect(sut.clipFrame.height == 0)
    }

    @Test
    func `the pin line sits the gap below the top inset whichever way the clip view's axis points`() {
        let bounds = CGRect(x: 0, y: 100, width: 400, height: 300)
        #expect(StickyCardGeometry.pinY(clipBounds: bounds, topInset: 52, gap: 16, isFlipped: true) == 168)
        #expect(StickyCardGeometry.pinY(clipBounds: bounds, topInset: 52, gap: 16, isFlipped: false) == 332)
    }
}

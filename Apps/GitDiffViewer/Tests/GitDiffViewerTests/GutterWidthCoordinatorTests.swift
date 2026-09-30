import AppKit
import DiffCore
import Testing

@testable import DiffRendering
@testable import DiffTextKit

/// One gutter width shared across a card list (book D43, "one gutter width across the card list"): every registered
/// gutter reads back the widest one any of them needs, and a width that does not move the shared one calls nothing
/// back, so a settled list causes no storm of invalidation.
@MainActor
@Suite(.mainActorLane)
struct GutterWidthCoordinatorTests {
    @Test
    func `the shared width is the widest any registered gutter needs`() {
        let sut = GutterWidthCoordinator()
        // Kept alive for the id's own lifetime: a deallocated object's identifier can be reused by the next one.
        let ownerA = NSObject()
        let ownerB = NSObject()
        let a = ObjectIdentifier(ownerA)
        let b = ObjectIdentifier(ownerB)

        sut.register(a, width: 40) {}
        sut.register(b, width: 60) {}

        #expect(sut.sharedWidth == 60)
    }

    @Test
    func `a card appearing with more digits widens every registered gutter together`() {
        let sut = GutterWidthCoordinator()
        // Kept alive for the id's own lifetime: a deallocated object's identifier can be reused by the next one.
        let ownerA = NSObject()
        let ownerB = NSObject()
        let a = ObjectIdentifier(ownerA)
        let b = ObjectIdentifier(ownerB)
        var notifiedA = 0
        var notifiedB = 0
        sut.register(a, width: 40) { notifiedA += 1 }
        sut.register(b, width: 40) { notifiedB += 1 }

        sut.update(b, width: 70)

        #expect(sut.sharedWidth == 70)
        // a's own registration already widened the shared width from zero, once; b's update widens it again.
        #expect(notifiedA == 2)
        #expect(notifiedB == 1)
    }

    @Test
    func `a card leaving drops its own width from the shared one`() {
        let sut = GutterWidthCoordinator()
        // Kept alive for the id's own lifetime: a deallocated object's identifier can be reused by the next one.
        let ownerA = NSObject()
        let ownerB = NSObject()
        let a = ObjectIdentifier(ownerA)
        let b = ObjectIdentifier(ownerB)
        sut.register(a, width: 40) {}
        sut.register(b, width: 70) {}

        sut.unregister(b)

        #expect(sut.sharedWidth == 40)
    }

    @Test
    func `registering or updating a width that does not move the shared one calls nothing back`() {
        let sut = GutterWidthCoordinator()
        // Kept alive for the id's own lifetime: a deallocated object's identifier can be reused by the next one.
        let ownerA = NSObject()
        let ownerB = NSObject()
        let a = ObjectIdentifier(ownerA)
        let b = ObjectIdentifier(ownerB)
        var notifiedB = 0
        sut.register(a, width: 70) {}
        sut.register(b, width: 40) { notifiedB += 1 }

        // Narrower than the shared width already in force, and still narrower after: neither call moves it.
        sut.update(b, width: 50)

        #expect(sut.sharedWidth == 70)
        #expect(notifiedB == 0)
    }

    @Test
    func `a gutter with a coordinator reports the shared width as its own thickness`() throws {
        let text = (1 ... 9).map { "let value\($0) = \($0)" }.joined(separator: "\n") + "\n"
        let wide = (1 ... 999).map { "let value\($0) = \($0)" }.joined(separator: "\n") + "\n"
        let narrow = try #require(DiffRenderer.render(oldText: text, newText: text, language: .plain).new)
        let wideRendered = try #require(DiffRenderer.render(oldText: wide, newText: wide, language: .plain).new)
        let coordinator = GutterWidthCoordinator()
        let small = DiffGutterView(clipView: nil)
        small.style = .new
        let big = DiffGutterView(clipView: nil)
        big.style = .new
        big.rendered = wideRendered
        let bigWidth = big.thickness

        small.widthCoordinator = coordinator
        big.widthCoordinator = coordinator
        small.rendered = narrow

        // The narrow file's own gutter would be thinner on its own; sharing the coordinator, it matches the widest.
        #expect(small.thickness == bigWidth)
        #expect(big.thickness == bigWidth)
    }
}

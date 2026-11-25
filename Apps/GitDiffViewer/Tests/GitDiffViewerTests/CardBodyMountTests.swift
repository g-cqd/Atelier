import Testing

@testable import DiffTextKit

/// ``CardBodyMount``: an unfolded card's body is mounted for its inputs, a fold keeps it until the card shows none of
/// it, and a folded card holds none. The inputs are plain integers standing for a render, a width and options.
struct CardBodyMountTests {
    private typealias SUT = CardBodyMount<Int>

    private func makeSUT(mountedWith inputs: Int? = nil) -> SUT {
        var sut = SUT()
        if let inputs { _ = sut.update(to: inputs, isCollapsed: false) }
        return sut
    }

    @Test
    func `an unfolded card mounts its body once it can lay it out`() {
        var sut = makeSUT()
        #expect(sut.update(to: nil, isCollapsed: false) == .none)
        #expect(sut.update(to: 1, isCollapsed: false) == .mount(1))
        #expect(sut.mounted == 1)
    }

    @Test
    func `the same inputs never mount the body twice`() {
        var sut = makeSUT(mountedWith: 1)
        #expect(sut.update(to: 1, isCollapsed: false) == .none)
    }

    @Test
    func `new inputs rebuild an unfolded card's body`() {
        var sut = makeSUT(mountedWith: 1)
        #expect(sut.update(to: 2, isCollapsed: false) == .mount(2))
        #expect(sut.mounted == 2)
    }

    @Test
    func `losing the width leaves an unfolded card's body as it is`() {
        var sut = makeSUT(mountedWith: 1)
        #expect(sut.update(to: nil, isCollapsed: false) == .none)
        #expect(sut.mounted == 1)
    }

    @Test
    func `a fold keeps the body until the card shows none of it, then unmounts it`() {
        var sut = makeSUT(mountedWith: 1)
        #expect(sut.update(to: 1, isCollapsed: true) == .none)
        #expect(sut.mounted == 1)
        #expect(sut.bodyHidden(isCollapsed: true) == .unmount)
        #expect(sut.mounted == nil)
        #expect(sut.bodyHidden(isCollapsed: true) == .none)
    }

    @Test
    func `an unfold before the fold finishes keeps the same body`() {
        var sut = makeSUT(mountedWith: 1)
        _ = sut.update(to: 1, isCollapsed: true)
        #expect(sut.update(to: 1, isCollapsed: false) == .none)
        #expect(sut.bodyHidden(isCollapsed: false) == .none)
        #expect(sut.mounted == 1)
    }

    @Test
    func `unfolding a folded card mounts its body again`() {
        var sut = makeSUT(mountedWith: 1)
        _ = sut.update(to: 1, isCollapsed: true)
        _ = sut.bodyHidden(isCollapsed: true)
        #expect(sut.update(to: 1, isCollapsed: false) == .mount(1))
    }

    @Test
    func `inputs that change while the card folds drop the body at once`() {
        var sut = makeSUT(mountedWith: 1)
        _ = sut.update(to: 1, isCollapsed: true)
        #expect(sut.update(to: 2, isCollapsed: true) == .unmount)
        #expect(sut.mounted == nil)
    }

    @Test
    func `a card that starts folded mounts nothing`() {
        var sut = makeSUT()
        #expect(sut.update(to: 1, isCollapsed: true) == .none)
        #expect(sut.bodyHidden(isCollapsed: true) == .none)
        #expect(sut.mounted == nil)
    }

    @Test
    func `an unfolded card that shows no body for a moment keeps it`() {
        var sut = makeSUT(mountedWith: 1)
        #expect(sut.bodyHidden(isCollapsed: false) == .none)
        #expect(sut.mounted == 1)
    }
}

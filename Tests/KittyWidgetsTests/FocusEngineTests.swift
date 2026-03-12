import Testing

@testable import KittyCodecs
@testable import KittyRenderer
@testable import KittySyntax
@testable import KittyWidgets

@Suite
struct FocusEngineTests {
    private func makeSUT(focusedIndex: Int = 0, focusableCount: Int = 3) -> FocusEngine {
        FocusEngine(focusedIndex: focusedIndex, focusableCount: focusableCount)
    }

    @Test func `initial focus index is zero by default`() {
        let sut = FocusEngine()
        #expect(sut.focusedIndex == 0)
    }

    @Test func `focusableCount is at least one`() {
        let sut = FocusEngine(focusedIndex: 0, focusableCount: 0)
        #expect(sut.focusableCount == 1)
    }

    @Test func `focusedIndex is at least zero`() {
        let sut = FocusEngine(focusedIndex: -5, focusableCount: 3)
        #expect(sut.focusedIndex == 0)
    }

    @Test func `focusNext increments the focused index`() {
        var sut = makeSUT()
        sut.focusNext()
        #expect(sut.focusedIndex == 1)
    }

    @Test func `focusNext increments through all indices sequentially`() {
        var sut = makeSUT(focusableCount: 3)
        sut.focusNext()
        #expect(sut.focusedIndex == 1)
        sut.focusNext()
        #expect(sut.focusedIndex == 2)
    }

    @Test func `focusNext wraps around from last to first`() {
        var sut = makeSUT(focusedIndex: 2, focusableCount: 3)
        sut.focusNext()
        #expect(sut.focusedIndex == 0)
    }

    @Test func `focusPrevious decrements the focused index`() {
        var sut = makeSUT(focusedIndex: 2, focusableCount: 3)
        sut.focusPrevious()
        #expect(sut.focusedIndex == 1)
    }

    @Test func `focusPrevious decrements through all indices sequentially`() {
        var sut = makeSUT(focusedIndex: 2, focusableCount: 3)
        sut.focusPrevious()
        #expect(sut.focusedIndex == 1)
        sut.focusPrevious()
        #expect(sut.focusedIndex == 0)
    }

    @Test func `focusPrevious wraps around from first to last`() {
        var sut = makeSUT(focusedIndex: 0, focusableCount: 3)
        sut.focusPrevious()
        #expect(sut.focusedIndex == 2)
    }

    @Test func `isFocused returns true for the focused index`() {
        let sut = makeSUT(focusedIndex: 1)
        #expect(sut.isFocused(1))
    }

    @Test func `isFocused returns false for non-focused indices`() {
        let sut = makeSUT(focusedIndex: 1, focusableCount: 3)
        #expect(!sut.isFocused(0))
        #expect(!sut.isFocused(2))
    }

    @Test func `single item focus wraps to itself on focusNext`() {
        var sut = FocusEngine(focusedIndex: 0, focusableCount: 1)
        sut.focusNext()
        #expect(sut.focusedIndex == 0)
    }

    @Test func `single item focus wraps to itself on focusPrevious`() {
        var sut = FocusEngine(focusedIndex: 0, focusableCount: 1)
        sut.focusPrevious()
        #expect(sut.focusedIndex == 0)
    }
}

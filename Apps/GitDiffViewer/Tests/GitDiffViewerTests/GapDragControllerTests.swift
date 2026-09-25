import AemiCore
import AemiTesting
import DiffCore
import Foundation
import Testing

@testable import DiffComparison
@testable import DiffRendering

/// A window's gap drags: pointer events become expansions, and a handle held in an edge zone keeps revealing at the
/// drag's bounded rate on the injected clock (book DIFF-02).
@MainActor
@Suite(.mainActorLane)
struct GapDragControllerTests {
    private let clock = TestClock()
    private let taskProvider = TaskProviderSpy.tolerant()
    /// Every expansion the controller revealed, in order.
    private let applied = AsyncProbe<GapExpansion>()

    /// A gap between two changes hiding `hidden` rows.
    private func between(hiding hidden: Int = 10) -> GapMarker {
        GapMarker(key: GapKey(fileIndex: 0, gapIndex: 1), hiddenRows: hidden, isLeading: false, isTrailing: false)
    }

    private func makeSUT(base: GapExpansion = GapExpansion()) -> GapDragController {
        GapDragController(
            taskProvider: taskProvider, clock: clock, expansion: { _ in base },
            apply: { [applied] expansion, _ in applied.send(expansion) })
    }

    @Test
    func `holding a handle in an edge zone reveals one more row per interval`() async throws {
        let sut = makeSUT()
        sut.handle(.began(between(), .extendsChangeAbove, lineHeight: 10))
        let hold = clock.registrationMark()
        sut.handle(.moved(offset: 20, edgeOvershoot: GapDrag.rampDepth))
        #expect(try await applied.expectNext() == GapExpansion(below: 2, above: 0))

        // The hold sleeps once per row it reveals.
        try await clock.expectSleepers(1, after: hold)
        clock.advance(by: GapDrag.fastestHold)
        #expect(try await applied.expectNext() == GapExpansion(below: 3, above: 0))
        try await clock.expectSleepers(2, after: hold)
        clock.advance(by: GapDrag.fastestHold)
        #expect(try await applied.expectNext() == GapExpansion(below: 4, above: 0))

        sut.handle(.ended)
        try await taskProvider.waitForAllTasks()
    }

    @Test
    func `holding stops when the pointer leaves the edge zone`() async throws {
        let sut = makeSUT()
        sut.handle(.began(between(), .extendsChangeAbove, lineHeight: 10))
        let hold = clock.registrationMark()
        sut.handle(.moved(offset: 20, edgeOvershoot: GapDrag.rampDepth))
        _ = try await applied.expectNext()
        try await clock.expectSleepers(after: hold)

        sut.handle(.moved(offset: 20, edgeOvershoot: 0))
        try await taskProvider.waitForAllTasks()
        clock.advance(by: .seconds(1))

        #expect(sut.drag?.revealed == 2)
        try applied.expectNoBufferedElements()
    }

    @Test
    func `holding stops at the last row the gap hides`() async throws {
        let sut = makeSUT()
        sut.handle(.began(between(hiding: 3), .extendsChangeAbove, lineHeight: 10))
        let hold = clock.registrationMark()
        sut.handle(.moved(offset: 20, edgeOvershoot: GapDrag.rampDepth))
        _ = try await applied.expectNext()
        try await clock.expectSleepers(after: hold)
        clock.advance(by: GapDrag.fastestHold)
        #expect(try await applied.expectNext() == GapExpansion(below: 3, above: 0))

        try await taskProvider.waitForAllTasks()
        #expect(sut.drag?.holdInterval == nil)
    }

    @Test
    func `ending a drag stops its hold`() async throws {
        let sut = makeSUT()
        sut.handle(.began(between(), .extendsChangeAbove, lineHeight: 10))
        let hold = clock.registrationMark()
        sut.handle(.moved(offset: 20, edgeOvershoot: GapDrag.rampDepth))
        _ = try await applied.expectNext()
        try await clock.expectSleepers(after: hold)

        sut.handle(.ended)
        try await taskProvider.waitForAllTasks()
        clock.advance(by: .seconds(1))

        #expect(sut.drag == nil)
        try applied.expectNoBufferedElements()
    }

    @Test
    func `a drag starts from the gap's expansion and returns to it at most`() async throws {
        let sut = makeSUT(base: GapExpansion(below: 1, above: 4))
        sut.handle(.began(between(), .extendsChangeBelow, lineHeight: 10))
        sut.handle(.moved(offset: -30, edgeOvershoot: 0))
        #expect(try await applied.expectNext() == GapExpansion(below: 1, above: 7))
        sut.handle(.moved(offset: 90, edgeOvershoot: 0))
        #expect(try await applied.expectNext() == GapExpansion(below: 1, above: 4))
    }

    @Test
    func `a handle the gap does not offer drags nothing`() throws {
        let sut = makeSUT()
        let topOfFile = GapMarker(
            key: GapKey(fileIndex: 0, gapIndex: 0), hiddenRows: 8, isLeading: true, isTrailing: false)
        sut.handle(.began(topOfFile, .extendsChangeAbove, lineHeight: 10))
        sut.handle(.moved(offset: 50, edgeOvershoot: 0))

        #expect(sut.drag == nil)
        try applied.expectNoBufferedElements()
    }

    @Test
    func `a double click reveals the whole gap from its handle's side`() async throws {
        let sut = makeSUT()
        sut.handle(.revealedAll(between(hiding: 10), .extendsChangeBelow))
        #expect(try await applied.expectNext() == GapExpansion(below: 0, above: 10))
    }
}

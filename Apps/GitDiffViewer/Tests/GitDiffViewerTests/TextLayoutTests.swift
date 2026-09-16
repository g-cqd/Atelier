import AemiCore
import AemiTesting
import AppKit
import DiffCore
import Testing

@testable import DiffComparison
@testable import DiffGit
@testable import DiffRendering
@testable import DiffTextKit

/// Forwards to a `TestClock` and counts the sleeps that ran to completion, which is how many debounced passes
/// a controller let through.
private final class CountingClock: Clock, Sendable {
    typealias Instant = TestClock.Instant
    typealias Duration = Swift.Duration

    let base = TestClock()
    let completedSleeps = CountProbe<Never>(label: "completedSleeps")

    var now: Instant { base.now }
    var minimumResolution: Duration { base.minimumResolution }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        try await base.sleep(until: deadline, tolerance: tolerance)
        completedSleeps.record()
    }
}

@MainActor
struct TextLayoutTests {
    private let old = "alpha\nbeta\ngamma\n"
    private let new = "alpha\n" + String(repeating: "beta ", count: 30) + "\ngamma\n"

    private func rendered() -> RenderedDiff {
        DiffRenderer.render(oldText: old, newText: new, language: .plain)
    }

    private static func fragmentHeights(of layoutManager: NSTextLayoutManager) -> [CGFloat] {
        layoutManager.ensureLayout(for: layoutManager.documentRange)
        var heights: [CGFloat] = []
        layoutManager.enumerateTextLayoutFragments(from: nil, options: [.ensuresLayout]) { fragment in
            heights.append(fragment.layoutFragmentFrame.height)
            return true
        }
        return heights
    }

    private static func textView(showing rendered: RenderedText, width: CGFloat) throws -> NSTextView {
        let textView = NSTextView(usingTextLayoutManager: true)
        let container = try #require(textView.textContainer)
        container.widthTracksTextView = false
        container.size = NSSize(width: width, height: DiffPaneMetrics.unboundedExtent)
        try #require(textView.textContentStorage?.textStorage).setAttributedString(rendered.attributed)
        return textView
    }

    // MARK: StaticTextLayout

    @Test
    func `a static layout measures one height per row and taller rows once lines wrap`() throws {
        let new = try #require(rendered().new)
        let layout = StaticTextLayout(rendered: new)

        layout.layOut(mode: .none, viewportWidth: 100)
        let unwrapped = layout.rowHeights()
        layout.layOut(mode: .viewport, viewportWidth: 100)
        let wrapped = layout.rowHeights()

        #expect(unwrapped.count == new.rows.count)
        #expect(wrapped.count == new.rows.count)
        #expect(Set(unwrapped).count == 1)
        #expect(wrapped[1] > unwrapped[1])
        #expect(wrapped[0] == unwrapped[0])
        #expect(wrapped[2] == unwrapped[2])
    }

    @Test
    func `preparing a split card gives paired rows the same height when only one side wraps`() throws {
        let layouts = CardLayouts(rendered: rendered())
        let old = try #require(layouts.old)
        let new = try #require(layouts.new)

        layouts.prepareSplit(width: 100, mode: .viewport)

        let oldHeights = Self.fragmentHeights(of: old.layoutManager)
        let newHeights = Self.fragmentHeights(of: new.layoutManager)
        #expect(oldHeights.count == 3)
        #expect(oldHeights == newHeights)
        #expect(old.rowHeights()[1] < new.rowHeights()[1])
        #expect(old.height == new.height)
    }

    // MARK: EmbeddedDiffTextView

    @Test
    func `an embedded pane shows the card layout's own storage and keeps selection across spacing changes`() throws {
        let layouts = CardLayouts(rendered: rendered())
        let old = try #require(layouts.old)
        let textView = NSTextView(usingTextLayoutManager: true)
        let container = try #require(textView.textContainer)
        container.widthTracksTextView = false
        container.size = NSSize(width: 100, height: DiffPaneMetrics.unboundedExtent)
        let coordinator = EmbeddedDiffTextView.Coordinator()
        coordinator.textView = textView

        coordinator.attach(old)
        textView.setSelectedRange(NSRange(location: 6, length: 4))
        layouts.prepareSplit(width: 100, mode: .viewport)

        #expect(textView.textContentStorage === old.contentStorage)
        #expect(textView.string == old.rendered.attributed.string)
        #expect(textView.selectedRange() == NSRange(location: 6, length: 4))
        #expect(textView.textLayoutManager?.delegate === old.fragmentProvider)
        let shown = try Self.fragmentHeights(of: #require(textView.textLayoutManager))
        #expect(shown == Self.fragmentHeights(of: old.layoutManager))
        #expect(shown[1] > shown[0])
    }

    @Test
    func `an embedded pane moves to a new card layout and leaves the storage when dismantled`() throws {
        let first = try #require(CardLayouts(rendered: rendered()).old)
        let second = try #require(CardLayouts(rendered: rendered()).new)
        let textView = NSTextView(usingTextLayoutManager: true)
        let coordinator = EmbeddedDiffTextView.Coordinator()
        coordinator.textView = textView

        coordinator.attach(first)
        coordinator.attach(second)
        #expect(first.contentStorage.textLayoutManagers.count == 1)
        #expect(textView.textContentStorage === second.contentStorage)
        #expect(textView.string == second.rendered.attributed.string)

        coordinator.detach()
        #expect(second.contentStorage.textLayoutManagers.count == 1)
        #expect(coordinator.layout == nil)
    }

    // MARK: SplitPaneController

    @Test
    func `a burst of alignment requests runs one pass once the debounce elapses`() async throws {
        let clock = CountingClock()
        let controller = SplitPaneController(clock: clock)
        let diff = rendered()
        let oldText = try #require(diff.old)
        let newText = try #require(diff.new)
        let leftView = try Self.textView(showing: oldText, width: 100)
        let rightView = try Self.textView(showing: newText, width: 100)
        controller.register(nil, textView: leftView)
        controller.register(nil, textView: rightView)

        controller.wrapsLines = true
        controller.update(oldText, for: leftView)
        controller.update(newText, for: rightView)
        try await clock.base.waitForSleepers()
        controller.scheduleAlignment()
        try await clock.base.waitForSleepers()
        clock.base.advance(by: SplitPaneController.alignmentDebounce)
        await controller.pendingAlignment?.value

        #expect(clock.completedSleeps.count == 1)
        let leftHeights = try Self.fragmentHeights(of: #require(leftView.textLayoutManager))
        let rightHeights = try Self.fragmentHeights(of: #require(rightView.textLayoutManager))
        #expect(leftHeights.count == 3)
        #expect(leftHeights == rightHeights)
    }

    @Test
    func `turning wrapping off removes the spacing an alignment added`() async throws {
        let clock = CountingClock()
        let controller = SplitPaneController(clock: clock)
        let diff = rendered()
        let oldText = try #require(diff.old)
        let newText = try #require(diff.new)
        let leftView = try Self.textView(showing: oldText, width: 100)
        let rightView = try Self.textView(showing: newText, width: 100)
        controller.register(nil, textView: leftView)
        controller.register(nil, textView: rightView)
        controller.update(oldText, for: leftView)
        controller.update(newText, for: rightView)
        controller.wrapsLines = true
        try await clock.base.waitForSleepers()
        clock.base.advance(by: SplitPaneController.alignmentDebounce)
        await controller.pendingAlignment?.value
        let aligned = try Self.fragmentHeights(of: #require(leftView.textLayoutManager))

        controller.wrapsLines = false
        try await clock.base.waitForSleepers()
        clock.base.advance(by: SplitPaneController.alignmentDebounce)
        await controller.pendingAlignment?.value

        let plain = try Self.fragmentHeights(of: #require(leftView.textLayoutManager))
        #expect(aligned[1] > plain[1])
        #expect(Set(plain).count == 1)
        #expect(clock.completedSleeps.count == 2)
    }

    @Test
    func `a document with no rows lays out without a row to colour`() {
        let rendered = DiffRenderer.render(oldText: "", newText: "", language: .plain)
        let layouts = CardLayouts(rendered: rendered)

        layouts.prepareSplit(width: 300, mode: .viewport)

        #expect(rendered.old?.rows.isEmpty == true)
        #expect(rendered.old?.row(containing: 0) == nil)
        #expect(layouts.old?.rowHeights().count == 0)
    }
}

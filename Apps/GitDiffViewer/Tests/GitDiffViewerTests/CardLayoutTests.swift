import DiffCore
import Testing

@testable import DiffComparison
@testable import DiffRendering

/// ``CardLayout`` and the layout controls' rules: a card lays its file out inline or side by side, and while the card
/// list shows, the controls disable stacked and select what the cards draw, without touching the stored choice.
struct CardLayoutTests {
    private static var otherDetails: [DetailState] {
        [
            .noSources, .loading, .error("unreadable"), .noSelection, .noChanges,
            .file(DiffRenderer.render(oldText: "a\n", newText: "b\n", language: .plain))
        ]
    }

    @Test(arguments: [(ViewMode.inline, CardLayout.inline), (.split, .split), (.stacked, .split)])
    func `a card lays every mode out inline or side by side`(mode: ViewMode, layout: CardLayout) {
        #expect(mode.cardLayout == layout)
    }

    @Test(arguments: ViewMode.allCases)
    func `while the card list shows, every mode but stacked is on offer`(mode: ViewMode) {
        #expect(mode.isAvailable(showing: .cards) == (mode != .stacked))
    }

    @Test(arguments: ViewMode.allCases)
    func `a single file and every other detail offer all three modes`(mode: ViewMode) {
        for detail in Self.otherDetails {
            #expect(mode.isAvailable(showing: detail), "\(mode) in \(detail)")
        }
    }

    @Test
    func `the card list shows a stacked choice as side by side, and the others as chosen`() {
        #expect(ViewMode.stacked.drawn(showing: .cards) == .split)
        #expect(ViewMode.split.drawn(showing: .cards) == .split)
        #expect(ViewMode.inline.drawn(showing: .cards) == .inline)
    }

    @Test
    func `outside the card list a stacked choice shows as stacked`() {
        for detail in Self.otherDetails {
            #expect(ViewMode.stacked.drawn(showing: detail) == .stacked, "\(detail)")
        }
    }
}

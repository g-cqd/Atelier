import Testing

@testable import DiffComparison

/// ``TabBarLayout``/``TabSlotContent``: the tab bar's own spacing constant, and the pure table behind what a tab's
/// fixed-size leading slot shows for a given hover/badge combination.
struct TabBarLayoutTests {
    @Test
    func `the bar's gap is six, the one constant tying inter-tab spacing to the bar's own insets`() {
        #expect(TabBarLayout.gap == 6)
    }

    @Test
    func `unhovered with a change shows the badge`() {
        #expect(TabSlotContent.resolve(isHovering: false, hasBadge: true) == .badge)
    }

    @Test
    func `unhovered with no change falls back to the neutral icon`() {
        #expect(TabSlotContent.resolve(isHovering: false, hasBadge: false) == .icon)
    }

    @Test
    func `hovering shows the close button in place of the badge`() {
        #expect(TabSlotContent.resolve(isHovering: true, hasBadge: true) == .close)
    }

    @Test
    func `hovering shows the close button in place of the icon fallback too`() {
        #expect(TabSlotContent.resolve(isHovering: true, hasBadge: false) == .close)
    }

    @Test
    func `hovering always wins over a badge, never showing both at once`() {
        let hoveredWithBadge = TabSlotContent.resolve(isHovering: true, hasBadge: true)
        let hoveredWithoutBadge = TabSlotContent.resolve(isHovering: true, hasBadge: false)
        #expect(hoveredWithBadge == hoveredWithoutBadge)
    }
}

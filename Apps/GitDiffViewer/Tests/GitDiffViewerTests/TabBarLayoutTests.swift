import Testing

@testable import DiffComparison

/// ``TabBarLayout``, ``TabSlotContent`` and ``TabAppearance``: the bar's spacing constant, what a tab's leading
/// slot shows, and how a tab draws for its pin, activity and hover state.
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

    @Test(arguments: [false, true], [false, true])
    func `a kept-open tab shows a pin after an upright name, active or hovered or not`(
        isActive: Bool, isHovering: Bool
    ) {
        let appearance = TabAppearance.resolve(
            isPinned: true, isActive: isActive, isHovering: isHovering, isHoveringClose: false)
        #expect(appearance.showsPin)
        #expect(!appearance.isItalic)
    }

    @Test(arguments: [false, true], [false, true])
    func `a preview tab shows an italic name and no pin, active or hovered or not`(isActive: Bool, isHovering: Bool) {
        let appearance = TabAppearance.resolve(
            isPinned: false, isActive: isActive, isHovering: isHovering, isHoveringClose: false)
        #expect(!appearance.showsPin)
        #expect(appearance.isItalic)
    }

    @Test(arguments: [false, true])
    func `hovering tones the capsule with a faint wash, and resting leaves it clear`(isActive: Bool) {
        let resting = TabAppearance.resolve(
            isPinned: true, isActive: isActive, isHovering: false, isHoveringClose: false)
        let hovered = TabAppearance.resolve(
            isPinned: true, isActive: isActive, isHovering: true, isHoveringClose: false)
        #expect(resting.washOpacity == 0)
        #expect(hovered.washOpacity > 0)
    }

    @Test(arguments: [false, true], [false, true])
    func `the active tab keeps a stronger outline and the primary ink whichever tab is hovered`(
        activeHovered: Bool, inactiveHovered: Bool
    ) {
        let active = TabAppearance.resolve(
            isPinned: true, isActive: true, isHovering: activeHovered, isHoveringClose: false)
        let inactive = TabAppearance.resolve(
            isPinned: true, isActive: false, isHovering: inactiveHovered, isHoveringClose: false)
        #expect(active.outlineOpacity > inactive.outlineOpacity)
        #expect(active.usesPrimaryInk)
        #expect(!inactive.usesPrimaryInk)
    }

    @Test
    func `the close button's disc shows only while the pointer is over the button itself`() {
        let overButton = TabAppearance.resolve(
            isPinned: true, isActive: false, isHovering: true, isHoveringClose: true)
        let overTab = TabAppearance.resolve(
            isPinned: true, isActive: false, isHovering: true, isHoveringClose: false)
        #expect(overButton.closeDiscOpacity > overButton.washOpacity)
        #expect(overTab.closeDiscOpacity == 0)
    }

    @Test
    func `a close hover left over after the pointer leaves the tab shows no disc`() {
        let stale = TabAppearance.resolve(isPinned: true, isActive: true, isHovering: false, isHoveringClose: true)
        #expect(stale.closeDiscOpacity == 0)
    }
}

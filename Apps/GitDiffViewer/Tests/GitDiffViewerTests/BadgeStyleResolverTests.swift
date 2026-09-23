import Testing

@testable import DiffComparison

/// ``BadgeStyleResolver``: filled for a committed change, stroked for an uncommitted one, inverted for a row
/// selected in a focused list.
struct BadgeStyleResolverTests {
    @Test
    func `staged, unselected: filled with the scheme's colour and a white letter`() {
        let style = BadgeStyleResolver.resolve(
            scheme: .classic, kind: .added, state: .staged, isSelected: false, isFocused: false)
        #expect(style == BadgeStyle(fill: .token(.green), stroke: nil, text: .white))
    }

    @Test
    func `unstaged, unselected: stroked, transparent fill, letter in the status colour`() {
        let style = BadgeStyleResolver.resolve(
            scheme: .classic, kind: .modified, state: .unstaged, isSelected: false, isFocused: false)
        #expect(style == BadgeStyle(fill: .none, stroke: .orange, text: .token(.orange)))
    }

    @Test
    func `untracked reads exactly like unstaged`() {
        let unstaged = BadgeStyleResolver.resolve(
            scheme: .classic, kind: .added, state: .unstaged, isSelected: false, isFocused: false)
        let untracked = BadgeStyleResolver.resolve(
            scheme: .classic, kind: .added, state: .untracked, isSelected: false, isFocused: false)
        #expect(unstaged == untracked)
    }

    @Test
    func `staged, selected in a focused list: inverts to a white fill and coloured letter`() {
        let style = BadgeStyleResolver.resolve(
            scheme: .classic, kind: .deleted, state: .staged, isSelected: true, isFocused: true)
        #expect(style == BadgeStyle(fill: .white, stroke: nil, text: .token(.red)))
    }

    @Test
    func `unstaged, selected in a focused list: inverts the same way staged does`() {
        let style = BadgeStyleResolver.resolve(
            scheme: .classic, kind: .deleted, state: .unstaged, isSelected: true, isFocused: true)
        #expect(style == BadgeStyle(fill: .white, stroke: nil, text: .token(.red)))
    }

    @Test
    func `selected but unfocused keeps the state's own look, not the inverted one`() {
        let selectedUnfocused = BadgeStyleResolver.resolve(
            scheme: .classic, kind: .modified, state: .staged, isSelected: true, isFocused: false)
        let unselected = BadgeStyleResolver.resolve(
            scheme: .classic, kind: .modified, state: .staged, isSelected: false, isFocused: false)
        #expect(selectedUnfocused == unselected)
    }

    @Test
    func `focused but not selected keeps the state's own look`() {
        let style = BadgeStyleResolver.resolve(
            scheme: .classic, kind: .modified, state: .staged, isSelected: false, isFocused: true)
        #expect(style == BadgeStyle(fill: .token(.orange), stroke: nil, text: .white))
    }

    @Test
    func `classic scheme colours every kind`() {
        #expect(BadgeStyleResolver.colorToken(for: .added, scheme: .classic) == .green)
        #expect(BadgeStyleResolver.colorToken(for: .deleted, scheme: .classic) == .red)
        #expect(BadgeStyleResolver.colorToken(for: .modified, scheme: .classic) == .orange)
        #expect(BadgeStyleResolver.colorToken(for: .renamed, scheme: .classic) == .purple)
    }

    @Test
    func `xcode scheme reads a modification and a rename both as blue`() {
        #expect(BadgeStyleResolver.colorToken(for: .added, scheme: .xcode) == .green)
        #expect(BadgeStyleResolver.colorToken(for: .deleted, scheme: .xcode) == .red)
        #expect(BadgeStyleResolver.colorToken(for: .modified, scheme: .xcode) == .blue)
        #expect(BadgeStyleResolver.colorToken(for: .renamed, scheme: .xcode) == .blue)
    }

    @Test
    func `xcode scheme still strokes an unstaged modification instead of filling it`() {
        let style = BadgeStyleResolver.resolve(
            scheme: .xcode, kind: .modified, state: .unstaged, isSelected: false, isFocused: false)
        #expect(style == BadgeStyle(fill: .none, stroke: .blue, text: .token(.blue)))
    }
}

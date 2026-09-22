import Testing

@testable import DiffComparison

/// ``AppearancePrecedence`` (Feature 2): an explicit light/dark pin always wins; `.system` only takes the theme's
/// own luminance when ``ViewerSettings/matchesThemeAppearance`` is on and a theme is actually selected.
struct AppearancePrecedenceTests {
    @Test
    func `an explicit light pin wins even when the toggle is on and the theme is dark`() {
        let resolved = AppearancePrecedence.resolve(explicit: .light, matchesTheme: true, themeIsDark: true)
        #expect(resolved == .light)
    }

    @Test
    func `an explicit dark pin wins even when the toggle is on and the theme is light`() {
        let resolved = AppearancePrecedence.resolve(explicit: .dark, matchesTheme: true, themeIsDark: false)
        #expect(resolved == .dark)
    }

    @Test
    func `system with the toggle off stays system regardless of the theme`() {
        #expect(AppearancePrecedence.resolve(explicit: .system, matchesTheme: false, themeIsDark: true) == .system)
        #expect(AppearancePrecedence.resolve(explicit: .system, matchesTheme: false, themeIsDark: false) == .system)
    }

    @Test
    func `system with the toggle on but no theme selected stays system`() {
        let resolved = AppearancePrecedence.resolve(explicit: .system, matchesTheme: true, themeIsDark: nil)
        #expect(resolved == .system)
    }

    @Test
    func `system with the toggle on and a dark theme resolves dark`() {
        let resolved = AppearancePrecedence.resolve(explicit: .system, matchesTheme: true, themeIsDark: true)
        #expect(resolved == .dark)
    }

    @Test
    func `system with the toggle on and a light theme resolves light`() {
        let resolved = AppearancePrecedence.resolve(explicit: .system, matchesTheme: true, themeIsDark: false)
        #expect(resolved == .light)
    }

    @Test
    func `the dark threshold is the documented midpoint`() {
        #expect(AppearancePrecedence.darkLuminanceThreshold == 0.5)
    }
}

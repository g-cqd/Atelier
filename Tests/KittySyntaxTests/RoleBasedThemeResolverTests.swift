import Testing

@testable import KittyCodecs
@testable import KittySyntax

@Suite
struct RoleBasedThemeResolverTests {
    @Test
    func `Role maps to correct theme style`() {
        let resolver = RoleBasedThemeResolver(theme: .monokai)
        let style = resolver.resolve(role: .keyword)
        #expect(style.bold)
        #expect(style.fg == .rgb(r: 249, g: 38, b: 114))
    }

    @Test
    func `Deprecated modifier applies strikethrough`() {
        let resolver = RoleBasedThemeResolver(theme: .monokai)
        let style = resolver.resolve(role: .variable, modifiers: .deprecated)
        #expect(style.strikethrough)
    }

    @Test
    func `Definition modifier applies bold`() {
        let resolver = RoleBasedThemeResolver(theme: .monokai)
        let style = resolver.resolve(role: .function, modifiers: .definition)
        #expect(style.bold)
    }

    @Test
    func `Role fallback uses theme hierarchy`() {
        let resolver = RoleBasedThemeResolver(theme: .monokai)
        // keywordFunction should fall back to keyword in theme
        let style = resolver.resolve(role: .keywordFunction)
        // Should get the keyword style since keyword.function falls back to keyword
        #expect(style.bold)
    }
}

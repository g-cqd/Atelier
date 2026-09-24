import AtelierSyntaxModel
import KittyStyle
import Testing

@testable import KittyCodecs
@testable import KittySyntax

@Suite
struct RoleBasedThemeResolverTests {
    /// A theme that styles some roles by their full capture name, some by a prefix only, and leaves the rest to its
    /// default, so each kind of lookup is checked.
    private static let partialTheme = Theme(
        styles: [
            "keyword": Style(fg: .rgb(r: 1, g: 2, b: 3), bold: true), "keyword.return": Style(italic: true),
            "function": Style(fg: .rgb(r: 4, g: 5, b: 6)), "comment": Style(dim: true)
        ],
        defaultStyle: Style(fg: .rgb(r: 7, g: 8, b: 9)))

    @Test(arguments: [Theme.monokai, partialTheme])
    func `a resolver that looks every role up at once resolves each as one that looks it up per token`(theme: Theme) {
        let perToken = RoleBasedThemeResolver(theme: theme)
        let precomputed = RoleBasedThemeResolver(precomputingStylesOf: theme)
        let modifierSets: [HighlightModifierSet] = [[], .deprecated, .documentation, .definition, [.definition, .async]]

        for role in HighlightRole.allCases {
            for modifiers in modifierSets {
                #expect(
                    precomputed.resolve(role: role, modifiers: modifiers)
                        == perToken.resolve(role: role, modifiers: modifiers))
            }
        }
    }

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

import Testing

@testable import KittyWidgets

// MARK: - Test Fixtures

private enum ThemeKey: EnvironmentKey {
    static let defaultValue = "light"
}

private enum FontSizeKey: EnvironmentKey {
    static let defaultValue = 14
}

// MARK: - EnvironmentValues Tests

@Suite
struct EnvironmentValuesTests {
    @Test func `subscript returns defaultValue when key is not set`() {
        let values = EnvironmentValues()

        #expect(values[ThemeKey.self] == "light")
        #expect(values[FontSizeKey.self] == 14)
    }

    @Test func `subscript stores and retrieves a set value`() {
        var values = EnvironmentValues()
        values[ThemeKey.self] = "dark"

        #expect(values[ThemeKey.self] == "dark")
    }

    @Test func `subscript setter overwrites a previously stored value`() {
        var values = EnvironmentValues()
        values[ThemeKey.self] = "dark"
        values[ThemeKey.self] = "high-contrast"

        #expect(values[ThemeKey.self] == "high-contrast")
    }

    @Test func `merging other takes precedence over self`() {
        var base = EnvironmentValues()
        base[ThemeKey.self] = "light"

        var override = EnvironmentValues()
        override[ThemeKey.self] = "dark"

        let merged = base.merging(override)

        #expect(merged[ThemeKey.self] == "dark")
    }

    @Test func `merging preserves keys only present in self`() {
        var base = EnvironmentValues()
        base[FontSizeKey.self] = 16

        let empty = EnvironmentValues()
        let merged = base.merging(empty)

        #expect(merged[FontSizeKey.self] == 16)
    }

    @Test func `merging adds keys only present in other`() {
        let base = EnvironmentValues()

        var other = EnvironmentValues()
        other[FontSizeKey.self] = 20

        let merged = base.merging(other)

        #expect(merged[FontSizeKey.self] == 20)
    }

    @Test func `merging does not mutate self`() {
        var base = EnvironmentValues()
        base[ThemeKey.self] = "light"

        var other = EnvironmentValues()
        other[ThemeKey.self] = "dark"

        _ = base.merging(other)

        #expect(base[ThemeKey.self] == "light")
    }

    @Test func `independent keys from separate EnvironmentValues are both preserved after merge`() {
        var base = EnvironmentValues()
        base[ThemeKey.self] = "light"

        var other = EnvironmentValues()
        other[FontSizeKey.self] = 18

        let merged = base.merging(other)

        #expect(merged[ThemeKey.self] == "light")
        #expect(merged[FontSizeKey.self] == 18)
    }
}

// MARK: - RenderContext.environmentValues Tests

@Suite
struct RenderContextEnvironmentTests {
    @Test func `default RenderContext has empty environmentValues returning defaults`() {
        let context = RenderContext()

        #expect(context.environmentValues[ThemeKey.self] == "light")
    }

    @Test func `merging RenderContext propagates environmentValues`() {
        var base = RenderContext()
        base.environmentValues[ThemeKey.self] = "dark"

        let merged = base.merging(RenderContext())

        #expect(merged.environmentValues[ThemeKey.self] == "dark")
    }

    @Test func `merging RenderContext lets other environmentValues win on conflict`() {
        var first = RenderContext()
        first.environmentValues[ThemeKey.self] = "light"

        var second = RenderContext()
        second.environmentValues[ThemeKey.self] = "dark"

        let merged = first.merging(second)

        #expect(merged.environmentValues[ThemeKey.self] == "dark")
    }
}

// MARK: - EnvironmentModifier Tests

@Suite
struct EnvironmentModifierTests {
    @Test func `modifyContext sets the key on environmentValues`() {
        let modifier = EnvironmentModifier<ThemeKey>(value: "dark")
        let ctx = modifier.modifyContext(RenderContext())

        #expect(ctx.environmentValues[ThemeKey.self] == "dark")
    }

    @Test func `modifyContext does not change unrelated context properties`() {
        var base = RenderContext()
        base.bold = true

        let modifier = EnvironmentModifier<ThemeKey>(value: "dark")
        let ctx = modifier.modifyContext(base)

        #expect(ctx.bold == true)
        #expect(ctx.foreground == nil)
    }

    @Test func `environment view modifier wraps view in ModifiedView with correct value`() {
        let view = Text("Hello").environment(ThemeKey.self, "dark")
        let modified = view as? ModifiedView<Text, EnvironmentModifier<ThemeKey>>

        #expect(modified != nil)
        #expect(modified?.modifier.value == "dark")
    }
}

import KittyCodecs
import KittyInput
import Testing

@testable import KittyEditor

@Suite
struct KeymapResolverOverrideTests {

    private func stroke(_ keyCode: UInt32, _ modifiers: KeyModifiers = []) -> KeyStroke {
        KeyStroke(keyCode: keyCode, modifiers: modifiers)
    }

    @Test
    func tabNextOverride() {
        var config = KittyConfig()
        config.keybindings.tabNext = "ctrl+j"
        let resolver = KeymapResolver(config: config)

        // New binding works
        #expect(resolver.resolve(stroke(AsciiKey.j, .ctrl), context: .editor) == .nextTab)
        // Old default removed
        #expect(resolver.resolve(stroke(Key.pageDown.rawValue, .ctrl), context: .editor) != .nextTab)
    }

    @Test
    func tabCloseOverride() {
        var config = KittyConfig()
        config.keybindings.tabClose = "ctrl+q"
        let resolver = KeymapResolver(config: config)

        #expect(resolver.resolve(stroke(AsciiKey.q, .ctrl), context: .editor) == .closeTab)
    }

    @Test
    func toggleSidebarOverride() {
        var config = KittyConfig()
        config.keybindings.toggleSidebar = "cmd+b"
        let resolver = KeymapResolver(config: config)

        // New binding
        #expect(resolver.resolve(stroke(AsciiKey.b, .super), context: .editor) == .toggleSidebar)
        // Old Ctrl+B removed
        #expect(resolver.resolve(stroke(AsciiKey.b, .ctrl), context: .editor) != .toggleSidebar)
    }

    @Test
    func defaultConfigNoOverrides() {
        let resolver = KeymapResolver(config: KittyConfig())

        // Defaults unchanged
        #expect(resolver.resolve(stroke(Key.pageDown.rawValue, .ctrl), context: .editor) == .nextTab)
        #expect(resolver.resolve(stroke(Key.pageUp.rawValue, .ctrl), context: .editor) == .previousTab)
        #expect(resolver.resolve(stroke(AsciiKey.b, .ctrl), context: .editor) == .toggleSidebar)
    }

    @Test
    func tabPrevOverride() {
        var config = KittyConfig()
        config.keybindings.tabPrev = "ctrl+k"
        let resolver = KeymapResolver(config: config)

        #expect(resolver.resolve(stroke(AsciiKey.k, .ctrl), context: .editor) == .previousTab)
        #expect(
            resolver.resolve(stroke(Key.pageUp.rawValue, .ctrl), context: .editor) != .previousTab)
    }

    @Test
    func invalidOverrideStringIgnored() {
        var config = KittyConfig()
        config.keybindings.tabNext = "foo+bar"
        let resolver = KeymapResolver(config: config)

        // Default still works when override is invalid
        #expect(resolver.resolve(stroke(Key.pageDown.rawValue, .ctrl), context: .editor) == .nextTab)
    }
}

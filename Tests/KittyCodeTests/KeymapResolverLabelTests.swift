import KittyCodecs
import KittyInput
import Testing

@testable import KittyCode

@Suite
struct KeymapResolverLabelTests {

    @Test
    func defaultSaveFile() {
        let resolver = KeymapResolver(config: KittyConfig())
        #expect(resolver.shortcutLabel(for: .saveFile) == "Ctrl+O")
    }

    @Test
    func defaultCopyWithCommandModifier() {
        let resolver = KeymapResolver(config: KittyConfig())
        let label = resolver.shortcutLabel(for: .copy)
        // Deterministic: prefers Cmd (super) over Meta
        #expect(label == "Cmd+C")
    }

    @Test
    func controlClipboardCopy() {
        var config = KittyConfig()
        config.keybindings.clipboardModifier = .control
        let resolver = KeymapResolver(config: config)
        let label = resolver.shortcutLabel(for: .copy)
        #expect(label != nil)
        #expect(label!.contains("Ctrl"))
    }

    @Test
    func closeTabNanoMode() {
        var config = KittyConfig()
        config.keybindingMode = .nano
        let resolver = KeymapResolver(config: config)
        #expect(resolver.shortcutLabel(for: .closeTab) == "Ctrl+W")
    }

    @Test
    func closeTabVimModeNotBound() {
        var config = KittyConfig()
        config.keybindingMode = .vim
        let resolver = KeymapResolver(config: config)
        #expect(resolver.shortcutLabel(for: .closeTab) == nil)
    }

    @Test
    func afterConfigOverride() {
        var config = KittyConfig()
        config.keybindings.tabClose = "ctrl+q"
        let resolver = KeymapResolver(config: config)
        #expect(resolver.shortcutLabel(for: .closeTab) == "Ctrl+Q")
    }

    @Test
    func statusHintsDefault() {
        let resolver = KeymapResolver(config: KittyConfig())
        let hints = resolver.statusHints()
        #expect(hints.contains("Save"))
        #expect(hints.contains("Quit"))
    }
}

import KittyCodecs
import KittyInput
import Testing

@testable import KittyCode

@Suite
struct KittyCodePresetTests {

    private func stroke(_ keyCode: UInt32, _ modifiers: KeyModifiers = []) -> KeyStroke {
        KeyStroke(keyCode: keyCode, modifiers: modifiers)
    }

    private func kittyCodeConfig() -> KittyConfig {
        var config = KittyConfig()
        config.keybindingMode = .kittycode
        return config
    }

    @Test
    func cmdSSaveFile() {
        let resolver = KeymapResolver(config: kittyCodeConfig())
        #expect(resolver.resolve(stroke(AsciiKey.s, .super), context: .editor) == .saveFile)
    }

    @Test
    func ctrlOFallbackSaveFile() {
        let resolver = KeymapResolver(config: kittyCodeConfig())
        #expect(resolver.resolve(stroke(AsciiKey.o, .ctrl), context: .editor) == .saveFile)
    }

    @Test
    func cmdWCloseTab() {
        let resolver = KeymapResolver(config: kittyCodeConfig())
        #expect(resolver.resolve(stroke(AsciiKey.w, .super), context: .editor) == .closeTab)
    }

    @Test
    func ctrlWFallbackCloseTab() {
        let resolver = KeymapResolver(config: kittyCodeConfig())
        #expect(resolver.resolve(stroke(AsciiKey.w, .ctrl), context: .editor) == .closeTab)
    }

    @Test
    func cmdBToggleSidebar() {
        let resolver = KeymapResolver(config: kittyCodeConfig())
        #expect(resolver.resolve(stroke(AsciiKey.b, .super), context: .editor) == .toggleSidebar)
    }

    @Test
    func ctrlBFallbackToggleSidebar() {
        let resolver = KeymapResolver(config: kittyCodeConfig())
        #expect(resolver.resolve(stroke(AsciiKey.b, .ctrl), context: .editor) == .toggleSidebar)
    }

    @Test
    func nanoModeCmdSNotBound() {
        let resolver = KeymapResolver(config: KittyConfig())
        #expect(resolver.resolve(stroke(AsciiKey.s, .super), context: .editor) == nil)
    }

    @Test
    func configOverrideInKittyCodeMode() {
        var config = kittyCodeConfig()
        config.keybindings.tabClose = "ctrl+q"
        let resolver = KeymapResolver(config: config)
        #expect(resolver.resolve(stroke(AsciiKey.q, .ctrl), context: .editor) == .closeTab)
    }

    @Test
    func saveFileLabelShowsCmdS() {
        let resolver = KeymapResolver(config: kittyCodeConfig())
        // Deterministic: prefers Cmd+S (super) over Ctrl+O fallback
        #expect(resolver.shortcutLabel(for: .saveFile) == "Cmd+S")
    }
}

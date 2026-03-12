import Foundation
import KittyCodecs
import KittyFileTree
import KittyGit
import KittyRenderer
import KittySyntax
import KittyTerminal
import KittyText
import KittyWidgets
import KittyWorkspace
import Testing

@testable import KittyCode

@Suite
struct TabPersistenceConfigTests {
    @Test
    func `tabPersistence defaults to pinned`() {
        let config = KittyConfig()
        #expect(config.tabRibbon.persistence == .pinned)
    }

    @Test
    func `tabPersistence decodes from JSON`() throws {
        let json = """
            {"tabRibbon": {"persistence": "preview"}}
            """
        let config = try JSONDecoder().decode(KittyConfig.self, from: Data(json.utf8))
        #expect(config.tabRibbon.persistence == .preview)
    }

    @Test
    func `old JSON without tabPersistence uses default`() throws {
        let json = """
            {"keybindingMode": "nano"}
            """
        let config = try JSONDecoder().decode(KittyConfig.self, from: Data(json.utf8))
        #expect(config.tabRibbon.persistence == .pinned)
    }
}

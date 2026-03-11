import Foundation
import Testing
@testable import KittySymbols

@Suite("KittySymbols")
struct KittySymbolsTests {
    @Test("Mapping entry derives glyph from codepoint")
    func mappingEntryGlyph() {
        let entry = SymbolMappingEntry(
            name: "folder",
            visibility: .publicSymbol,
            assetGlyphIndex: 77,
            codepoint: 0x100215
        )

        #expect(entry.glyph == "􀈕")
    }

    @Test("Terminal symbol theme falls back without catalog")
    func themeFallback() {
        let theme = TerminalSymbolTheme.make(symbolsEnabled: false, catalog: nil)

        #expect(theme[.folderClosed].text == ">")
        #expect(theme[.file].text == "-")
    }

    @Test("Terminal symbol theme uses mapped glyphs")
    func themeUsesCatalogGlyphs() {
        let catalog = SymbolCatalog(entries: [
            "folder": SymbolMappingEntry(name: "folder", visibility: .publicSymbol, assetGlyphIndex: 77, codepoint: 0x100215),
            "folder.fill": SymbolMappingEntry(name: "folder.fill", visibility: .publicSymbol, assetGlyphIndex: 78, codepoint: 0x100216),
            "doc.text": SymbolMappingEntry(name: "doc.text", visibility: .publicSymbol, assetGlyphIndex: 575, codepoint: 0x10023F),
        ])

        let theme = TerminalSymbolTheme.make(symbolsEnabled: true, catalog: catalog)

        #expect(theme[.folderClosed].prefersSymbol)
        #expect(theme[.folderClosed].text == "􀈕")
        #expect(theme[.folderOpen].text == "􀈖")
        #expect(theme[.file].text == "􀈿")
    }

    @Test("All roles have non-empty fallback text")
    func allRolesHaveFallbacks() {
        let theme = TerminalSymbolTheme.make(symbolsEnabled: false, catalog: nil)
        for role in TerminalSymbolTheme.Role.allCases {
            #expect(!theme[role].text.isEmpty, "Role \(role) has empty fallback")
        }
    }

    @Test("New git roles have correct fallbacks")
    func gitRoleFallbacks() {
        let theme = TerminalSymbolTheme.make(symbolsEnabled: false, catalog: nil)
        #expect(theme[.gitModified].text == "M")
        #expect(theme[.gitAdded].text == "A")
        #expect(theme[.gitUntracked].text == "?")
        #expect(theme[.gitDeleted].text == "D")
        #expect(theme[.gitConflicted].text == "!")
        #expect(theme[.dirty].text == "●")
        #expect(theme[.close].text == "×")
    }
}

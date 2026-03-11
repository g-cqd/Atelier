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
            "text.document": SymbolMappingEntry(name: "text.document", visibility: .publicSymbol, assetGlyphIndex: 575, codepoint: 0x10023F),
        ])

        let theme = TerminalSymbolTheme.make(symbolsEnabled: true, catalog: catalog)

        #expect(theme[.folderClosed].prefersSymbol)
        #expect(theme[.folderClosed].text == "􀈕")
        #expect(theme[.folderOpen].text == "􀈖")
        #expect(theme[.file].text == "􀈿")
    }
}

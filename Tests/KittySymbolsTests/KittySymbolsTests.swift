import Foundation
import Testing
@testable import KittySymbols

@Suite
struct KittySymbolsTests {
    @Test
    func `Mapping entry derives glyph from codepoint`() {
        let entry = SymbolMappingEntry(
            name: "folder",
            visibility: .publicSymbol,
            assetGlyphIndex: 77,
            codepoint: 0x100215
        )

        #expect(entry.glyph == "􀈕")
    }

    @Test
    func `Terminal symbol theme falls back without catalog`() {
        let theme = TerminalSymbolTheme.make(symbolsEnabled: false, catalog: nil)

        #expect(theme[.folderClosed].text == ">")
        #expect(theme[.file].text == "-")
    }

    @Test
    func `Terminal symbol theme uses mapped glyphs`() {
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

    @Test
    func `All roles have non-empty fallback text`() {
        let theme = TerminalSymbolTheme.make(symbolsEnabled: false, catalog: nil)
        for role in TerminalSymbolTheme.Role.allCases {
            #expect(!theme[role].text.isEmpty, "Role \(role) has empty fallback")
        }
    }

    @Test
    func `Explorer and openDocuments roles have correct fallbacks`() {
        let theme = TerminalSymbolTheme.make(symbolsEnabled: false, catalog: nil)
        #expect(theme[.explorer].text == "E")
        #expect(theme[.openDocuments].text == "D")
    }

    @Test
    func `Explorer role resolves to SF Symbol glyph when catalog available`() {
        let catalog = SymbolCatalog(entries: [
            "folder.fill": SymbolMappingEntry(name: "folder.fill", visibility: .publicSymbol, assetGlyphIndex: 78, codepoint: 0x100216),
        ])
        let theme = TerminalSymbolTheme.make(symbolsEnabled: true, catalog: catalog)
        #expect(theme[.explorer].prefersSymbol)
        #expect(theme[.explorer].text == "􀈖")
    }

    @Test
    func `New git roles have correct fallbacks`() {
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

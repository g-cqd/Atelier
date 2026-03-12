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
    func `Terminal symbol theme uses hardcoded PUA codepoints`() {
        let theme = TerminalSymbolTheme.make(symbolsEnabled: true, catalog: nil)

        #expect(theme[.folderClosed].prefersSymbol)
        #expect(theme[.folderClosed].text == "\u{1003ED}")
        #expect(theme[.folderOpen].text == "\u{100A9B}")
        #expect(theme[.file].text == "\u{1018F6}")
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
        #expect(theme[.explorer].text == "F")
        #expect(theme[.openDocuments].text == "O")
    }

    @Test
    func `Explorer role resolves to hardcoded SF Symbol glyph`() {
        let theme = TerminalSymbolTheme.make(symbolsEnabled: true, catalog: nil)
        #expect(theme[.explorer].prefersSymbol)
        #expect(theme[.explorer].text == "\u{1003ED}")
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

    @Test
    func `Symbol catalog loader discovers and caches mappings when file is missing`() {
        let mappingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let collection = SymbolCollection(records: [
            SymbolRecord(
                name: "folder.fill",
                visibility: .publicSymbol,
                assetGlyphIndex: 78,
                codepoint: 0x100216,
                glyph: "􀈖",
                availability: nil,
                categories: [],
                searchTerms: []
            )
        ])

        let catalog = SymbolCatalogLoader.loadOrDiscover(
            mappingURL: mappingURL,
            discover: { collection }
        )

        #expect(catalog?["folder.fill"]?.glyph == "􀈖")
        #expect(FileManager.default.fileExists(atPath: mappingURL.path))
    }
}

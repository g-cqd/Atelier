import Foundation
import Testing

@testable import KittySymbols

/// A hand-edited mapping file, or a symbol order listing a name twice, must load rather than trap the editor at
/// launch in `Dictionary(uniqueKeysWithValues:)`.
@Suite
struct SymbolDuplicateNameTests {
    private static let first = SymbolMappingEntry(
        name: "folder", visibility: .publicSymbol, assetGlyphIndex: 1, codepoint: 0x100215)
    private static let second = SymbolMappingEntry(
        name: "folder", visibility: .privateSymbol, assetGlyphIndex: 2, codepoint: 0x100216)

    private static func record(_ entry: SymbolMappingEntry) -> SymbolRecord {
        SymbolRecord(
            name: entry.name, visibility: entry.visibility, assetGlyphIndex: entry.assetGlyphIndex,
            codepoint: entry.codepoint, glyph: entry.glyph, availability: nil, categories: [], searchTerms: [])
    }

    private static func temporaryMappingURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
    }

    @Test
    func `a mapping file listing a name twice loads with the first entry`() throws {
        let url = Self.temporaryMappingURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try SymbolJSONWriter.writeMappings([Self.first, Self.second], to: url)

        let catalog = try SymbolCatalog.load(from: url)

        #expect(catalog.entries.count == 1)
        #expect(catalog["folder"] == Self.first)
    }

    @Test
    func `discovered symbols listing a name twice load with the first entry`() {
        let url = Self.temporaryMappingURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let collection = SymbolCollection(records: [Self.record(Self.first), Self.record(Self.second)])

        let catalog = SymbolCatalogLoader.loadOrDiscover(mappingURL: url, discover: { collection })

        #expect(catalog?.entries.count == 1)
        #expect(catalog?["folder"] == Self.first)
    }

    @Test
    func `discovery keeps the first record of a name listed twice`() {
        let trash = SymbolMappingEntry(name: "trash", visibility: .publicSymbol, assetGlyphIndex: 3, codepoint: nil)
        let trashAgain = SymbolMappingEntry(
            name: "trash", visibility: .publicSymbol, assetGlyphIndex: 9, codepoint: nil)
        let records = [Self.first, trash, Self.second, trashAgain].map(Self.record)

        let unique = SymbolDiscovery.removingDuplicateNames(records)

        #expect(unique.map(\.mappingEntry) == [Self.first, trash])
    }
}

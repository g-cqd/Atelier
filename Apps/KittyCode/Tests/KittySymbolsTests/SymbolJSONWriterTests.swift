import Foundation
import Testing

@testable import KittySymbols

/// The catalog files keep the layout Foundation's `[.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]` gave
/// them, and read back through Foundation's `JSONDecoder`, which `SymbolCatalog` still uses.
@Suite
struct SymbolJSONWriterTests {
    private let mappings = [
        SymbolMappingEntry(name: "folder/badge", visibility: .publicSymbol, assetGlyphIndex: 77, codepoint: 0x10_0215),
        SymbolMappingEntry(name: "private.glyph", visibility: .privateSymbol, assetGlyphIndex: nil, codepoint: nil)
    ]

    @Test
    func `mappings are written byte for byte as Foundation's encoder wrote them`() throws {
        let url = temporaryURL()

        try SymbolJSONWriter.writeMappings(mappings, to: url)

        #expect(try Data(contentsOf: url) == foundationEncoder().encode(mappings))
    }

    @Test
    func `a collection without empty lists is written byte for byte as Foundation's encoder wrote it`() throws {
        let collection = SymbolCollection(
            generatedAt: Date(timeIntervalSince1970: 1_790_000_000.75),
            records: [
                SymbolRecord(
                    name: "folder/badge", visibility: .publicSymbol, assetGlyphIndex: 77, codepoint: 0x10_0215,
                    glyph: "\u{100215}", availability: "13.0", categories: ["objects"], searchTerms: ["dossier", "é"])
            ])
        let url = temporaryURL()
        let encoder = foundationEncoder()
        encoder.dateEncodingStrategy = .iso8601

        try SymbolJSONWriter.writeCollection(collection, to: url)

        #expect(try Data(contentsOf: url) == encoder.encode(collection))
    }

    @Test
    func `a collection with empty lists reads back through Foundation's decoder`() throws {
        let collection = SymbolCollection(
            generatedAt: Date(timeIntervalSince1970: 1_790_000_000),
            records: [
                SymbolRecord(
                    name: "folder", visibility: .publicSymbol, assetGlyphIndex: nil, codepoint: nil, glyph: nil,
                    availability: nil, categories: [], searchTerms: [])
            ])
        let url = temporaryURL()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        try SymbolJSONWriter.writeCollection(collection, to: url)

        #expect(try decoder.decode(SymbolCollection.self, from: Data(contentsOf: url)) == collection)
    }

    private func foundationEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "symbols-\(UUID().uuidString).json")
    }
}

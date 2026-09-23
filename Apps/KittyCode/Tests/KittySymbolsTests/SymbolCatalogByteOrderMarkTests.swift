import Foundation
import Testing

@testable import KittySymbols

/// A mapping file saved with a UTF-8 byte-order mark, which Foundation's decoder accepted, still loads.
@Suite
struct SymbolCatalogByteOrderMarkTests {
    @Test
    func `a mapping file behind a byte-order mark loads`() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        defer { try? FileManager.default.removeItem(at: url) }
        let entry = SymbolMappingEntry(
            name: "folder", visibility: .publicSymbol, assetGlyphIndex: 1, codepoint: 0x100215)
        try SymbolJSONWriter.writeMappings([entry], to: url)
        try (Data([0xEF, 0xBB, 0xBF]) + Data(contentsOf: url)).write(to: url)

        #expect(try SymbolCatalog.load(from: url)["folder"] == entry)
    }
}

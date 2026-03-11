import Foundation

public enum SymbolJSONWriter {
    public static func writeCollection(_ collection: SymbolCollection, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(collection).write(to: url)
    }

    public static func writeMappings(_ mappings: [SymbolMappingEntry], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(mappings).write(to: url)
    }
}

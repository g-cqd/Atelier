import AemiJSON
public import Foundation

public enum SymbolJSONWriter {
    public static func writeCollection(_ collection: SymbolCollection, to url: URL) throws {
        var encoder = catalogEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(collection).write(to: url)
    }

    public static func writeMappings(_ mappings: [SymbolMappingEntry], to url: URL) throws {
        try catalogEncoder().encode(mappings).write(to: url)
    }

    /// The layout of Foundation's `[.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]`, which people diff the
    /// catalog files in: two-space indents, `" : "` between key and value, sorted keys, unescaped slashes. An empty
    /// list or object is written on one line, where Foundation broke it over three.
    private static func catalogEncoder() -> AemiJSON.JSONEncoder {
        var encoder = AemiJSON.JSONEncoder()
        encoder.options = JSONEncodingOptions(
            keyOrder: .sorted, escapeSlashes: false, prettyPrinted: true, prettyKeySeparator: .foundation,
            indent: .spaces(2))
        return encoder
    }
}

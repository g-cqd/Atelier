import Foundation

public struct SymbolCatalog: Sendable {
    public let entries: [String: SymbolMappingEntry]

    public init(entries: [String: SymbolMappingEntry]) {
        self.entries = entries
    }

    public subscript(_ name: String) -> SymbolMappingEntry? {
        entries[name]
    }

    public static func load(from url: URL) throws -> SymbolCatalog {
        let data = try Data(contentsOf: url)
        let mappings = try JSONDecoder().decode([SymbolMappingEntry].self, from: data)
        let entries = Dictionary(uniqueKeysWithValues: mappings.map { ($0.name, $0) })
        return SymbolCatalog(entries: entries)
    }
}

public enum SymbolCatalogLocator {
    public static func defaultMappingURL(fileManager: FileManager = .default) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".kittycode-sf-symbols.json")
    }
}

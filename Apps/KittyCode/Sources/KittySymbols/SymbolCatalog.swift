public import Foundation

public struct SymbolCatalog: Sendable {
    public let entries: [String: SymbolMappingEntry]

    public init(entries: [String: SymbolMappingEntry]) {
        self.entries = entries
    }

    /// A catalog of `mappings` keyed by name, keeping the first mapping of a name listed more than once.
    /// - Complexity: O(n)
    public init(mappings: [SymbolMappingEntry]) {
        self.init(entries: Dictionary(mappings.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first }))
    }

    public subscript(_ name: String) -> SymbolMappingEntry? {
        entries[name]
    }

    public static func load(from url: URL) throws -> SymbolCatalog {
        let data = try Data(contentsOf: url)
        let mappings = try JSONDecoder().decode([SymbolMappingEntry].self, from: data)
        return SymbolCatalog(mappings: mappings)
    }
}

public enum SymbolCatalogLocator {
    public static func defaultMappingURL(fileManager: FileManager = .default) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".kittycode-sf-symbols.json")
    }
}

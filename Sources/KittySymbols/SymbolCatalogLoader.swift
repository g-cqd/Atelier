import Foundation

public enum SymbolCatalogLoader {
    public typealias Discover = @Sendable () throws -> SymbolCollection
    public typealias WriteMappings = @Sendable ([SymbolMappingEntry], URL) throws -> Void

    public static func loadOrDiscover(
        mappingURL: URL = SymbolCatalogLocator.defaultMappingURL(),
        fileManager: FileManager = .default,
        discover: Discover = { try SymbolDiscovery().discover() },
        writeMappings: WriteMappings = { mappings, url in
            try SymbolJSONWriter.writeMappings(mappings, to: url)
        }
    ) -> SymbolCatalog? {
        if let catalog = try? SymbolCatalog.load(from: mappingURL) {
            return catalog
        }

        guard let collection = try? discover() else {
            return nil
        }

        let mappings = collection.mappings
        guard !mappings.isEmpty else { return nil }

        try? fileManager.createDirectory(
            at: mappingURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try? writeMappings(mappings, mappingURL)

        return SymbolCatalog(
            entries: Dictionary(uniqueKeysWithValues: mappings.map { ($0.name, $0) })
        )
    }
}

import Foundation
import KittySymbols

@main
struct KittySymbolsCLI {
    static func main() {
        do {
            let discovery = SymbolDiscovery()
            let collection = try discovery.discover()

            let outputURL = SymbolCatalogLocator.defaultMappingURL()
            try SymbolJSONWriter.writeMappings(collection.mappings, to: outputURL)

            let detailedURL = outputURL.deletingPathExtension().appendingPathExtension("full.json")
            try SymbolJSONWriter.writeCollection(collection, to: detailedURL)

            FileHandle.standardOutput.write(
                Data("Wrote \(collection.records.count) symbols to \(outputURL.path)\n".utf8)
            )
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            Foundation.exit(1)
        }
    }
}

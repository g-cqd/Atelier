import Foundation

struct SymbolMetadataLoader {
    struct Metadata: Sendable {
        let searchTermsByName: [String: [String]]
        let categoriesByName: [String: [String]]
        let availabilityByName: [String: String]
    }

    func loadFrameworkMetadata(from bundleURL: URL) throws -> Metadata {
        return Metadata(
            searchTermsByName: (try? loadStringArrayDictionary(
                at: bundleURL.appending(path: "symbol_search.plist"))) ?? [:],
            categoriesByName: (try? loadStringArrayDictionary(
                at: bundleURL.appending(path: "symbol_categories.plist"))) ?? [:],
            availabilityByName: (try? loadAvailability(
                at: bundleURL.appending(path: "name_availability.plist"))) ?? [:]
        )
    }

    private func loadStringArrayDictionary(at url: URL) throws -> [String: [String]] {
        let data = try Data(contentsOf: url)
        guard
            let dictionary = try PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: [String]]
        else {
            throw SymbolDiscoveryError.invalidPropertyList(url.path)
        }
        return dictionary
    }

    private func loadAvailability(at url: URL) throws -> [String: String] {
        let data = try Data(contentsOf: url)
        guard
            let dictionary = try PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any],
            let symbols = dictionary["symbols"] as? [String: String]
        else {
            throw SymbolDiscoveryError.invalidPropertyList(url.path)
        }
        return symbols
    }
}

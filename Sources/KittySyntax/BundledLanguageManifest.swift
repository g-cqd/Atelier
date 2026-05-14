import Foundation
import KittySync
import System

struct BundledLanguageEntry: Decodable, Sendable, Equatable {
    let name: String
    let extensions: [String]
    let path: String
}

enum BundledLanguageManifest {
    private struct Manifest: Sendable {
        let entries: [BundledLanguageEntry]
        let entriesByLanguage: [String: BundledLanguageEntry]
        let entriesByExtension: [String: BundledLanguageEntry]
    }

    private struct Storage: Sendable {
        var didLoad = false
        var manifest: Manifest?
    }

    private static let storage = StateLock(initialState: Storage())

    static var entries: [BundledLanguageEntry] {
        loadedManifest()?.entries ?? []
    }

    static func entry(forLanguage language: String) -> BundledLanguageEntry? {
        loadedManifest()?.entriesByLanguage[language]
    }

    static func entry(forFilename filename: String) -> BundledLanguageEntry? {
        let fileExtension = (FilePath(filename).extension ?? "").lowercased()
        guard !fileExtension.isEmpty else { return nil }
        return loadedManifest()?.entriesByExtension[".\(fileExtension)"]
    }

    private static func loadedManifest() -> Manifest? {
        let cached = storage.withLock { state -> Manifest? in
            guard state.didLoad else { return nil }
            return state.manifest
        }
        if let cached {
            return cached
        }

        let manifest = loadManifest()
        return storage.withLock { state in
            if state.didLoad {
                return state.manifest
            }

            state.didLoad = true
            state.manifest = manifest
            return state.manifest
        }
    }

    private static func loadManifest() -> Manifest? {
        guard
            let manifestURL = KittySyntaxResources.bundle.url(
                forResource: "languages",
                withExtension: "json",
                subdirectory: "Grammars"
            ), let data = try? Data(contentsOf: manifestURL),
            let decodedEntries = try? JSONDecoder().decode([BundledLanguageEntry].self, from: data)
        else {
            return nil
        }

        let normalizedEntries = decodedEntries.map { entry in
            BundledLanguageEntry(
                name: entry.name,
                extensions: entry.extensions.map(Self.normalizeExtension),
                path: entry.path
            )
        }

        let entriesByLanguage = Dictionary(
            uniqueKeysWithValues: normalizedEntries.map { ($0.name, $0) })
        let entriesByExtension = normalizedEntries.reduce(into: [String: BundledLanguageEntry]()) {
            result, entry in
            for fileExtension in entry.extensions {
                result[fileExtension] = entry
            }
        }

        return Manifest(
            entries: normalizedEntries,
            entriesByLanguage: entriesByLanguage,
            entriesByExtension: entriesByExtension
        )
    }

    private static func normalizeExtension(_ fileExtension: String) -> String {
        let trimmed = fileExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return trimmed }
        return trimmed.hasPrefix(".") ? trimmed : ".\(trimmed)"
    }
}

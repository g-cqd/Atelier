import Foundation
import Synchronization
import System
import os

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

    private static let storage = Mutex(Storage())

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

    /// Logger for manifest load failures. Bundled resource missing or
    /// corrupted is the only way `loadManifest` returns nil — that should
    /// not be silent because it disables every grammar-backed highlighter
    /// at runtime. Audit D5.
    private static let logger = Logger(
        subsystem: "kittycode.kittysyntax", category: "bundled-language-manifest")

    private static func loadManifest() -> Manifest? {
        guard
            let manifestURL = KittySyntaxResources.bundle.url(
                forResource: "languages",
                withExtension: "json",
                subdirectory: "Grammars"
            )
        else {
            logger.fault("languages.json missing from KittySyntax resource bundle")
            return nil
        }
        let data: Data
        do {
            data = try Data(contentsOf: manifestURL)
        } catch {
            logger.fault(
                "languages.json read failed at \(manifestURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
        let decodedEntries: [BundledLanguageEntry]
        do {
            decodedEntries = try JSONDecoder().decode([BundledLanguageEntry].self, from: data)
        } catch {
            logger.fault(
                "languages.json decode failed: \(error.localizedDescription, privacy: .public)")
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

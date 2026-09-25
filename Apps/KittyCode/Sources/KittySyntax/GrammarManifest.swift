public import Foundation
import System

/// A `languages.json` manifest: the languages a grammar corpus holds, looked up by name and by file name.
public struct GrammarManifest: Sendable, Equatable {
    /// A manifest that names no language.
    public static let empty = GrammarManifest(entries: [])

    /// The entries in manifest order, each extension lowercased with one leading dot.
    public let entries: [GrammarRegistry.LanguageEntry]
    private let entriesByLanguage: [String: GrammarRegistry.LanguageEntry]
    private let entriesByExtension: [String: GrammarRegistry.LanguageEntry]

    public init(entries: [GrammarRegistry.LanguageEntry]) {
        let normalizedEntries = entries.map { entry in
            GrammarRegistry.LanguageEntry(
                name: entry.name,
                extensions: entry.extensions.map(Self.normalizeExtension),
                path: entry.path
            )
        }
        self.entries = normalizedEntries
        entriesByLanguage = Dictionary(uniqueKeysWithValues: normalizedEntries.map { ($0.name, $0) })
        entriesByExtension = normalizedEntries.reduce(into: [String: GrammarRegistry.LanguageEntry]()) {
            result, entry in
            for fileExtension in entry.extensions {
                result[fileExtension] = entry
            }
        }
    }

    /// The manifest `data` holds, a JSON array of entries.
    /// - Throws: `JSONError` or `DecodingError` when `data` is not one.
    public static func decode(_ data: Data) throws -> GrammarManifest {
        GrammarManifest(entries: try SyntaxJSON.decode([GrammarRegistry.LanguageEntry].self, from: data))
    }

    public func entry(forLanguage language: String) -> GrammarRegistry.LanguageEntry? {
        entriesByLanguage[language]
    }

    /// The entry for the exact dotfile name of `filename`, else for its lowercased extension.
    public func entry(forFilename filename: String) -> GrammarRegistry.LanguageEntry? {
        let path = FilePath(filename)
        if let basename = path.lastComponent?.string, basename.hasPrefix("."),
            let entry = entriesByExtension[basename.lowercased()]
        {
            return entry
        }
        let fileExtension = (path.extension ?? "").lowercased()
        guard !fileExtension.isEmpty else { return nil }
        return entriesByExtension[".\(fileExtension)"]
    }

    public static func == (lhs: GrammarManifest, rhs: GrammarManifest) -> Bool {
        lhs.entries == rhs.entries
    }

    private static func normalizeExtension(_ fileExtension: String) -> String {
        let trimmed = fileExtension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return trimmed }
        return trimmed.hasPrefix(".") ? trimmed : ".\(trimmed)"
    }
}

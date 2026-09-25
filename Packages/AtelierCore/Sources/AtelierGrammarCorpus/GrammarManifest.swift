import AemiJSON
import AemiKernel
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

    /// A manifest of `entries`. A language named twice keeps its first entry for lookups by name, and an extension
    /// listed twice its last.
    public init(entries: [GrammarRegistry.LanguageEntry]) {
        let normalizedEntries = entries.map { entry in
            GrammarRegistry.LanguageEntry(
                name: entry.name,
                extensions: entry.extensions.map(Self.normalizeExtension),
                path: entry.path
            )
        }
        self.entries = normalizedEntries
        entriesByLanguage = Dictionary(normalizedEntries.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        entriesByExtension = normalizedEntries.reduce(into: [String: GrammarRegistry.LanguageEntry]()) {
            result, entry in
            for fileExtension in entry.extensions {
                result[fileExtension] = entry
            }
        }
    }

    /// The manifest in the file at `url`.
    /// - Throws: `GrammarManifestError.unreadable` when the file can't be read, or the error of ``decode(_:)``.
    public static func load(from url: URL) throws(GrammarManifestError) -> GrammarManifest {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw .unreadable(path: url.path)
        }
        return try decode(data)
    }

    /// The manifest `data` holds: a JSON array of entries, each an object with a `name`, an `extensions` array of
    /// strings and a `path`. An entry with a member missing or mistyped is skipped, as is one whose `path` is not a
    /// single safe name, since a manifest is untrusted and `../..` would reach outside the corpus. A key repeated in an
    /// entry keeps its last value. A leading byte-order mark is skipped.
    /// - Throws: `GrammarManifestError.invalidJSON` when `data` is not JSON or nests too deep, `.notAnArrayOfEntries`
    ///   when it is not an array of objects.
    /// - Complexity: O(n) in the size of `data`.
    public static func decode(_ data: Data) throws(GrammarManifestError) -> GrammarManifest {
        let document: JSONDocument
        do {
            document = try SyntaxJSON.parse(data)
        } catch {
            throw .invalidJSON(String(describing: error))
        }
        guard let items = document.root.array, items.allSatisfy(\.isObject) else {
            throw .notAnArrayOfEntries
        }
        let entries = items.compactMap { item in
            (try? SyntaxJSON.decode(GrammarRegistry.LanguageEntry.self, from: item))
                .flatMap { isSafePathToken($0.path) ? $0 : nil }
        }
        return GrammarManifest(entries: entries)
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

    /// Whether `value` is one ASCII name of letters, digits, `_`, `-` and `.`, and neither `..` nor `~` in it.
    private static func isSafePathToken(_ value: String) -> Bool {
        guard !value.isEmpty,
            !value.hasPrefix("~"),
            !value.contains(".."),
            !value.contains("/"),
            !value.contains("\\")
        else { return false }
        return value.allSatisfy { ch in
            guard let byte = ch.asciiValue else { return false }
            return ASCII.isAlphanumeric(byte) || ch == "_" || ch == "-" || ch == "."
        }
    }
}

/// Why a `languages.json` manifest could not be read.
public enum GrammarManifestError: Error, Sendable, Equatable {
    /// The file at `path` could not be read.
    case unreadable(path: String)
    /// The data is not JSON, or nests deeper than a manifest may; the associated value describes the JSON error.
    case invalidJSON(String)
    /// The JSON is not an array of entry objects.
    case notAnArrayOfEntries
}

import Foundation
import KittyGrammar

/// Maps file extensions to grammar definitions.
/// Loads `languages.json` and auto-discovers grammar bundles.
public actor GrammarRegistry {
    // extension → entry
    private var entries: [String: LanguageEntry] = [:]
    // language name → grammar
    private var loadedGrammars: [String: GrammarDefinition] = [:]
    // language name → compiled result
    private var compiledTables: [String: ParseTableCompiler.CompilationResult] = [:]

    public struct LanguageEntry: Sendable, Equatable {
        public var name: String
        public var extensions: [String]
        public var path: String

        public init(name: String, extensions: [String], path: String) {
            self.name = name
            self.extensions = extensions
            self.path = path
        }
    }

    public init() {}

    /// Register a language entry.
    public func register(_ entry: LanguageEntry) {
        for ext in entry.extensions {
            entries[ext] = entry
        }
    }

    /// Load entries from a languages.json file.
    public func loadManifest(from path: String) throws(GrammarError) {
        let url = URL(fileURLWithPath: path)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw .fileNotFound(path)
        }
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw .invalidJSON(String(describing: error))
        }
        guard let array = json as? [[String: Any]] else {
            throw .invalidJSON("Expected array of language entries")
        }
        for item in array {
            guard let name = item["name"] as? String,
                let extensions = item["extensions"] as? [String],
                let path = item["path"] as? String
            else { continue }
            register(LanguageEntry(name: name, extensions: extensions, path: path))
        }
    }

    /// Find the language entry for a file extension.
    public func entry(forExtension ext: String) -> LanguageEntry? {
        let normalized = ext.hasPrefix(".") ? ext : ".\(ext)"
        return entries[normalized]
    }

    /// Load and cache a grammar definition for a language.
    public func grammar(for languageName: String, grammarsPath: String) throws(GrammarError)
        -> GrammarDefinition
    {
        if let cached = loadedGrammars[languageName] { return cached }

        let entry = entries.values.first { $0.name == languageName }
        guard let entry else { throw .fileNotFound("No entry for language: \(languageName)") }

        let grammarPath = "\(grammarsPath)/\(entry.path)/grammar.json"
        let grammar = try GrammarLoader.load(from: grammarPath)
        loadedGrammars[languageName] = grammar
        return grammar
    }

    /// Return a compiled parse table result for the given language.
    ///
    /// Lookup order:
    /// 1. In-memory cache (`compiledTables`).
    /// 2. Disk cache at `<tmp>/kittycode-cache/<languageName>.ptable` (JSON-encoded `CompilationResult`).
    /// 3. Fresh compilation from the grammar file, persisted to disk cache.
    public func compiledResult(
        for languageName: String,
        grammarsPath: String
    ) throws(GrammarError) -> ParseTableCompiler.CompilationResult {
        if let cached = compiledTables[languageName] { return cached }

        let cacheURL = Self.cacheDirectory.appendingPathComponent("\(languageName).ptable")
        if let result = try? loadFromDisk(at: cacheURL) {
            compiledTables[languageName] = result
            return result
        }

        let grammarDefinition = try grammar(for: languageName, grammarsPath: grammarsPath)
        let result = try ParseTableCompiler.compile(grammarDefinition)
        compiledTables[languageName] = result
        try? saveToDisk(result, at: cacheURL)
        return result
    }

    /// All registered language names.
    public var languageNames: [String] {
        Array(Set(entries.values.map(\.name))).sorted()
    }

    // MARK: - Private disk-cache helpers

    private static let cacheDirectory: URL =
        FileManager.default.temporaryDirectory.appendingPathComponent("kittycode-cache")

    private func loadFromDisk(at url: URL) throws -> ParseTableCompiler.CompilationResult {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ParseTableCompiler.CompilationResult.self, from: data)
    }

    private func saveToDisk(_ result: ParseTableCompiler.CompilationResult, at url: URL) throws {
        try FileManager.default.createDirectory(
            at: Self.cacheDirectory,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(result)
        try data.write(to: url, options: .atomic)
    }
}

// MARK: - Syntax Error

public enum SyntaxError: Error, Sendable, Equatable {
    case unsupportedLanguage(String)
    case grammarLoadFailed(String)
    case queryLoadFailed(String)
    case highlightingFailed(String)
}

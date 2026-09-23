import AemiJSON
import AemiKernel
public import AtelierGrammar
import Foundation
import Synchronization

/// The runtime registry of language grammars: registered entries, loaded grammars, and compiled parse tables cached
/// in memory and on disk. Its state sits behind a `Mutex`, so synchronous callers on any thread can use it.
public final class GrammarRegistry: Sendable {
    /// The process-wide registry, which the highlighter consults before `BundledLanguageManifest`.
    public static let shared = GrammarRegistry()

    private struct State: Sendable {
        /// Entries keyed by file extension, dot included (`.swift`).
        var entries: [String: LanguageEntry] = [:]
        /// `entries` keyed by language name, kept in step by `register(_:)`.
        var entriesByLanguage: [String: LanguageEntry] = [:]
        var loadedGrammars: [String: GrammarDefinition] = [:]
        var compiledTables: [String: ParseTableCompiler.CompilationResult] = [:]
    }

    private let state = Mutex(State())

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

    /// Registers `entry` under its name and, verbatim, under each of its extensions; lookups add a leading dot, so
    /// an extension registered without one is never found.
    public func register(_ entry: LanguageEntry) {
        state.withLock { state in
            for ext in entry.extensions {
                state.entries[ext] = entry
            }
            state.entriesByLanguage[entry.name] = entry
        }
    }

    /// Registers the entries of a `languages.json` file (`name`, `extensions`, `path`), skipping malformed ones and
    /// any whose `path` isn't a single safe name. A key repeated in one entry keeps its first value.
    /// - Throws: `GrammarError.fileNotFound` when the file can't be read, `.invalidJSON` when it isn't an array of
    ///   entries.
    public func loadManifest(from path: String) throws(GrammarError) {
        let url = URL(fileURLWithPath: path)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw .fileNotFound(path)
        }
        let document: JSONDocument
        do {
            document = try SyntaxJSON.parse(data)
        } catch {
            throw .invalidJSON(String(describing: error))
        }
        guard let items = document.root.array, items.allSatisfy(\.isObject) else {
            throw .invalidJSON("Expected array of language entries")
        }
        for item in items {
            let entry = ManifestEntryMembers(item)
            guard let name = entry.name?.string,
                let extensions = entry.extensions.flatMap(Self.strings),
                let path = entry.path?.string
            else { continue }
            // The manifest is untrusted: a `path` like `../../etc` would read files outside the grammar root.
            guard Self.isSafePathToken(path) else { continue }
            register(LanguageEntry(name: name, extensions: extensions, path: path))
        }
    }

    /// The elements of an array of strings; nil when `node` is not an array or holds anything but strings.
    private static func strings(_ node: JSON) -> [String]? {
        guard let elements = node.array else { return nil }
        let strings = elements.compactMap(\.string)
        return strings.count == elements.count ? strings : nil
    }

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

    /// Find the language entry for a file extension.
    public func entry(forExtension ext: String) -> LanguageEntry? {
        let normalized = ext.hasPrefix(".") ? ext : ".\(ext)"
        return state.withLock { $0.entries[normalized] }
    }

    /// The entry registered under `languageName`, with no fallback to the bundled manifest.
    public func entry(forLanguage languageName: String) -> LanguageEntry? {
        state.withLock { $0.entriesByLanguage[languageName] }
    }

    /// The entry registered for the lowercased extension of `filename`; nil when it has none.
    public func entry(forFilename filename: String) -> LanguageEntry? {
        let ext = (filename as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return nil }
        return entry(forExtension: ext)
    }

    /// The grammar of `languageName`, loaded once from its registered entry, else its bundled one, and cached.
    /// - Throws: `GrammarError.fileNotFound` when neither names the language, or the grammar loader's error.
    public func grammar(for languageName: String, grammarsPath: String) throws(GrammarError)
        -> GrammarDefinition
    {
        if let cached = state.withLock({ $0.loadedGrammars[languageName] }) {
            return cached
        }

        let resolvedEntry: LanguageEntry
        if let registered = entry(forLanguage: languageName) {
            resolvedEntry = registered
        } else if let bundled = BundledLanguageManifest.entry(forLanguage: languageName) {
            resolvedEntry = LanguageEntry(bundled: bundled)
        } else {
            throw .fileNotFound("No entry for language: \(languageName)")
        }

        let grammarPath = "\(grammarsPath)/\(resolvedEntry.path)/grammar.json"
        let grammar = try GrammarLoader.load(from: grammarPath)
        state.withLock { $0.loadedGrammars[languageName] = grammar }
        return grammar
    }

    /// The compiled parse tables of `languageName`: from memory, else from `<tmp>/kittycode-cache/<name>.ptable`,
    /// else compiled from the grammar and saved there.
    /// - Throws: The `GrammarError` of loading or compiling the grammar.
    public func compiledResult(
        for languageName: String,
        grammarsPath: String
    ) throws(GrammarError) -> ParseTableCompiler.CompilationResult {
        if let cached = state.withLock({ $0.compiledTables[languageName] }) {
            return cached
        }

        let cacheURL = Self.cacheDirectory.appendingPathComponent("\(languageName).ptable")
        if let result = try? loadFromDisk(at: cacheURL) {
            state.withLock { $0.compiledTables[languageName] = result }
            return result
        }

        let grammarDefinition = try grammar(for: languageName, grammarsPath: grammarsPath)
        let result = try ParseTableCompiler.compile(grammarDefinition)
        state.withLock { $0.compiledTables[languageName] = result }
        try? saveToDisk(result, at: cacheURL)
        return result
    }

    /// All registered language names.
    public var languageNames: [String] {
        state.withLock { Array(Set($0.entries.values.map(\.name))).sorted() }
    }

    // MARK: - Private disk-cache helpers

    private static let cacheDirectory: URL =
        FileManager.default.temporaryDirectory.appendingPathComponent("kittycode-cache")

    private func loadFromDisk(at url: URL) throws -> ParseTableCompiler.CompilationResult {
        try Self.decodeCompiledTables(from: Data(contentsOf: url))
    }

    private func saveToDisk(_ result: ParseTableCompiler.CompilationResult, at url: URL) throws {
        try FileManager.default.createDirectory(
            at: Self.cacheDirectory,
            withIntermediateDirectories: true
        )
        try Self.encodeCompiledTables(result).write(to: url, options: .atomic)
    }

    /// The compiled tables a cache file holds, whether AemiJSON or Foundation's `JSONEncoder` wrote it.
    /// - Throws: `JSONError` or `DecodingError` when `data` is not a cache file.
    static func decodeCompiledTables(from data: Data) throws -> ParseTableCompiler.CompilationResult {
        try SyntaxJSON.decode(ParseTableCompiler.CompilationResult.self, from: data)
    }

    /// The contents of a cache file for `result`.
    static func encodeCompiledTables(_ result: ParseTableCompiler.CompilationResult) throws -> Data {
        try SyntaxJSON.encode(result)
    }
}

/// The members a manifest entry reads, each the first of its key.
private struct ManifestEntryMembers {
    var name: JSON?
    var extensions: JSON?
    var path: JSON?

    /// Visits `object`'s members once.
    init(_ object: JSON) {
        object.forEachMember { key, value in
            switch key {
                case "name": name = name ?? value
                case "extensions": extensions = extensions ?? value
                case "path": path = path ?? value
                default: break
            }
        }
    }
}

// MARK: - Bundled entry bridge

extension GrammarRegistry.LanguageEntry {
    /// A bundled entry in registry form, for lookups that fall back to the bundled manifest.
    init(bundled: BundledLanguageEntry) {
        self.init(name: bundled.name, extensions: bundled.extensions, path: bundled.path)
    }
}

// MARK: - Syntax Error

public enum SyntaxError: Error, Sendable, Equatable {
    case unsupportedLanguage(String)
    case grammarLoadFailed(String)
    case queryLoadFailed(String)
    case highlightingFailed(String)
}

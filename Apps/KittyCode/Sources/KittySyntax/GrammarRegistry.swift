import AemiJSON
import AemiKernel
public import AtelierGrammar
import Foundation
import Synchronization

/// The runtime registry of language grammars: registered entries, loaded grammars, and compiled parse tables and
/// failed compiles, cached in memory and on disk. Its state sits behind a `Mutex`, so synchronous callers on any
/// thread can use it.
public final class GrammarRegistry: Sendable {
    /// The process-wide registry, which the highlighter consults before `BundledLanguageManifest`.
    public static let shared = GrammarRegistry()

    private struct State: Sendable {
        /// Entries keyed by file extension, lowercased and dot included (`.swift`).
        var entries: [String: LanguageEntry] = [:]
        /// `entries` keyed by language name, kept in step by `register(_:)`.
        var entriesByLanguage: [String: LanguageEntry] = [:]
        /// Each language's grammar, read once per registration.
        var loadedGrammars: [String: LoadedGrammar] = [:]
        /// What compiling each grammar file gave, tables or the compiler's error: the same bytes compile the same way.
        var compileOutcomes: [CompiledTableCache.Key: Result<ParseTableCompiler.CompilationResult, GrammarError>] = [:]
    }

    /// A language's grammar and the cache key of the bytes it was parsed from, so tables compiled from it are never
    /// stored under the key of another version of its file.
    private struct LoadedGrammar: Sendable {
        var definition: GrammarDefinition
        var key: CompiledTableCache.Key
    }

    private let state = Mutex(State())
    private let diskCache: CompiledTableCache
    private let compile: @Sendable (GrammarDefinition) throws(GrammarError) -> ParseTableCompiler.CompilationResult

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

    public convenience init() {
        self.init(cacheDirectory: CompiledTableCache.defaultDirectory) { grammar throws(GrammarError) in
            try ParseTableCompiler.compile(grammar)
        }
    }

    /// A registry that keeps its disk cache in `cacheDirectory` and compiles grammars with `compile`.
    init(
        cacheDirectory: URL,
        compile: @escaping @Sendable (GrammarDefinition) throws(GrammarError) -> ParseTableCompiler.CompilationResult
    ) {
        self.diskCache = CompiledTableCache(directory: cacheDirectory)
        self.compile = compile
    }

    /// Registers `entry` under its name and under each of its extensions, which it keeps in the form every lookup
    /// asks for, lowercased with one leading dot: `json`, `.json` and `.JSON` all register `.json`. A grammar loaded
    /// for the language under an earlier registration is dropped, so its next use reads the new entry's file.
    public func register(_ entry: LanguageEntry) {
        var normalized = entry
        normalized.extensions = entry.extensions.map(Self.normalizedExtension)
        state.withLock { state in
            for ext in normalized.extensions {
                state.entries[ext] = normalized
            }
            state.entriesByLanguage[normalized.name] = normalized
            state.loadedGrammars[normalized.name] = nil
        }
    }

    /// `ext` lowercased, with one leading dot.
    private static func normalizedExtension(_ ext: String) -> String {
        let lowercased = ext.lowercased()
        return lowercased.hasPrefix(".") ? lowercased : ".\(lowercased)"
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

    /// The entry registered for a file extension, given with or without its leading dot, in any case.
    public func entry(forExtension ext: String) -> LanguageEntry? {
        let normalized = Self.normalizedExtension(ext)
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
        try loadedGrammar(for: languageName, grammarsPath: grammarsPath).definition
    }

    /// `languageName`'s grammar and the cache key of its file's bytes, both from one read of the file.
    private func loadedGrammar(for languageName: String, grammarsPath: String) throws(GrammarError) -> LoadedGrammar {
        if let loaded = state.withLock({ $0.loadedGrammars[languageName] }) {
            return loaded
        }
        let contents = try GrammarLoader.contents(ofFileAt: grammarPath(for: languageName, grammarsPath: grammarsPath))
        let loaded = LoadedGrammar(
            definition: try GrammarLoader.parse(contents),
            key: CompiledTableCache.Key(language: languageName, grammar: contents))
        state.withLock { $0.loadedGrammars[languageName] = loaded }
        return loaded
    }

    /// The compiled parse tables of `languageName`: from memory, else from the disk cache, else compiled and stored
    /// there.
    ///
    /// Both caches key a grammar by the SHA-256 of its file and ``ParseTableCompiler/formatVersion``, so an edited
    /// grammar or a newer compiler compiles again. A compile that fails is remembered under the same key, in memory
    /// and on disk, and later calls, in this process or the next, throw its error at once: the same grammar fails
    /// the same way, some only after many seconds.
    /// - Throws: The error of loading the grammar, or of compiling it, whether now or when first tried.
    public func compiledResult(
        for languageName: String,
        grammarsPath: String
    ) throws(GrammarError) -> ParseTableCompiler.CompilationResult {
        let grammar = try loadedGrammar(for: languageName, grammarsPath: grammarsPath)
        if let outcome = state.withLock({ $0.compileOutcomes[grammar.key] }) {
            return try outcome.get()
        }

        let outcome: Result<ParseTableCompiler.CompilationResult, GrammarError>
        if let stored = diskCache.outcome(for: grammar.key) {
            outcome = stored
        } else {
            outcome = Result { () throws(GrammarError) in try compile(grammar.definition) }
            diskCache.store(outcome, for: grammar.key)
        }
        state.withLock { $0.compileOutcomes[grammar.key] = outcome }
        return try outcome.get()
    }

    /// The path of `languageName`'s grammar file, from its registered entry, else its bundled one.
    /// - Throws: `GrammarError.fileNotFound` when neither names the language.
    private func grammarPath(for languageName: String, grammarsPath: String) throws(GrammarError) -> String {
        let resolvedEntry: LanguageEntry
        if let registered = entry(forLanguage: languageName) {
            resolvedEntry = registered
        } else if let bundled = BundledLanguageManifest.entry(forLanguage: languageName) {
            resolvedEntry = LanguageEntry(bundled: bundled)
        } else {
            throw .fileNotFound("No entry for language: \(languageName)")
        }
        return "\(grammarsPath)/\(resolvedEntry.path)/grammar.json"
    }

    /// All registered language names.
    public var languageNames: [String] {
        state.withLock { Array(Set($0.entries.values.map(\.name))).sorted() }
    }

    // MARK: - Cache file contents

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

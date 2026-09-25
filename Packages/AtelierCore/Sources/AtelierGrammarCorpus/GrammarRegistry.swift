public import AtelierGrammar
public import Foundation
import Synchronization

/// The runtime registry of language grammars: registered entries, loaded grammars, and compiled parse tables and
/// failed compiles, cached in memory and on disk. Its state sits behind a `Mutex`. A language no entry is registered
/// for falls back to its bundled manifest's entry.
public final class GrammarRegistry: Sendable {
    private struct State: Sendable {
        /// Entries keyed by file extension, lowercased and dot included (`.swift`).
        var entries: [String: LanguageEntry] = [:]
        /// `entries` keyed by language name, kept in step by `register(_:)`.
        var entriesByLanguage: [String: LanguageEntry] = [:]
        /// Each language's grammar, read once per registration.
        var loadedGrammars: [String: LoadedGrammar] = [:]
        /// What compiling each grammar file gave, tables or the compiler's error: the same bytes compile the same way.
        var compileOutcomes: [CompiledTableCache.Key: Result<ParseTableCompiler.CompilationResult, GrammarError>] = [:]
        /// One task per file and compiler version while a compile or disk read is in progress.
        var compilesInFlight:
            [CompiledTableCache.Key: Task<Result<ParseTableCompiler.CompilationResult, GrammarError>, Never>] = [:]
    }

    /// A language's grammar and the cache key of the bytes it was parsed from, so tables compiled from it are never
    /// stored under the key of another version of its file.
    private struct LoadedGrammar: Sendable {
        var definition: GrammarDefinition
        var key: CompiledTableCache.Key
    }

    private let state = Mutex(State())
    private let diskCache: CompiledTableCache
    /// The entries a language without a registered one falls back to.
    private let bundledManifest: GrammarManifest
    private let compile:
        @Sendable (GrammarDefinition) async throws(GrammarError) -> ParseTableCompiler.CompilationResult

    public struct LanguageEntry: Sendable, Equatable, Decodable {
        public var name: String
        public var extensions: [String]
        public var path: String

        public init(name: String, extensions: [String], path: String) {
            self.name = name
            self.extensions = extensions
            self.path = path
        }
    }

    /// A registry that keeps its disk cache in `cacheDirectory`, which the app chooses, and falls back to
    /// `bundledManifest` for a language registered nowhere else.
    public convenience init(cacheDirectory: URL, bundledManifest: GrammarManifest = .empty) {
        self.init(cacheDirectory: cacheDirectory, bundledManifest: bundledManifest) { grammar throws(GrammarError) in
            try ParseTableCompiler.compile(grammar)
        }
    }

    /// A registry that keeps its disk cache in `cacheDirectory` and compiles grammars with `compile`.
    init(
        cacheDirectory: URL,
        bundledManifest: GrammarManifest = .empty,
        compile:
            @escaping @Sendable (GrammarDefinition) async throws(GrammarError) -> ParseTableCompiler.CompilationResult
    ) {
        self.diskCache = CompiledTableCache(directory: cacheDirectory)
        self.bundledManifest = bundledManifest
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

    /// Registers the entries of the `languages.json` file at `path`, skipping those ``GrammarManifest/decode(_:)``
    /// skips: malformed ones and any whose `path` isn't a single safe name.
    /// - Throws: `GrammarManifestError.unreadable` when the file can't be read, `.invalidJSON` when it isn't JSON,
    ///   `.notAnArrayOfEntries` when it isn't an array of entries.
    public func loadManifest(from path: String) throws(GrammarManifestError) {
        for entry in try GrammarManifest.load(from: URL(fileURLWithPath: path)).entries {
            register(entry)
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

    /// The entry registered for the lowercased extension or exact dotfile name of `filename`.
    public func entry(forFilename filename: String) -> LanguageEntry? {
        let path = filename as NSString
        let basename = path.lastPathComponent
        if basename.hasPrefix("."), let entry = entry(forExtension: basename) { return entry }
        let ext = path.pathExtension.lowercased()
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
    ) async throws(GrammarError) -> ParseTableCompiler.CompilationResult {
        let grammar = try loadedGrammar(for: languageName, grammarsPath: grammarsPath)
        if let outcome = state.withLock({ $0.compileOutcomes[grammar.key] }) {
            return try outcome.get()
        }
        let task = state.withLock { state in
            if let existing = state.compilesInFlight[grammar.key] { return existing }
            let task = Task.detached(priority: .utility) { [compile, diskCache] in
                if let stored = diskCache.outcome(for: grammar.key) { return stored }
                let outcome: Result<ParseTableCompiler.CompilationResult, GrammarError>
                do {
                    outcome = .success(try await compile(grammar.definition))
                } catch let error as GrammarError {
                    outcome = .failure(error)
                } catch {
                    outcome = .failure(.invalidRuleType("Unexpected compiler failure: \(error)"))
                }
                diskCache.store(outcome, for: grammar.key)
                return outcome
            }
            state.compilesInFlight[grammar.key] = task
            return task
        }
        let outcome = await task.value
        state.withLock { state in
            state.compileOutcomes[grammar.key] = outcome
            state.compilesInFlight[grammar.key] = nil
        }
        return try outcome.get()
    }

    /// Reads a compiled table only when it is already cached; prewarming never starts a compile.
    public func cachedResult(
        for languageName: String, grammarsPath: String
    ) throws(GrammarError) -> ParseTableCompiler.CompilationResult? {
        let grammar = try loadedGrammar(for: languageName, grammarsPath: grammarsPath)
        guard let stored = diskCache.outcome(for: grammar.key) else { return nil }
        return try stored.get()
    }

    /// The entry of `languageName`: its registered one, else its bundled one.
    public func resolvedEntry(forLanguage languageName: String) -> LanguageEntry? {
        entry(forLanguage: languageName) ?? bundledManifest.entry(forLanguage: languageName)
    }

    /// The path of `languageName`'s grammar file, from its registered entry, else its bundled one.
    /// - Throws: `GrammarError.fileNotFound` when neither names the language.
    private func grammarPath(for languageName: String, grammarsPath: String) throws(GrammarError) -> String {
        guard let resolvedEntry = resolvedEntry(forLanguage: languageName) else {
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

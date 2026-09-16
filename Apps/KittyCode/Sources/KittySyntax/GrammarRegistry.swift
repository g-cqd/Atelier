import Foundation
public import KittyGrammar
import Synchronization

/// Runtime registry of language-grammar bindings.
///
/// Loads `languages.json` manifests, holds compiled parse tables in
/// memory and a backing disk cache, and dispatches `entry(for*: …)`
/// lookups for `SyntaxArtifactsCache` and (eventually) ADR 8
/// extensions. Previously an `actor` — now a `Sendable final class`
/// over `Mutex<State>` so callers in synchronous contexts
/// (`SyntaxArtifactsCache.loadArtifacts`, `LanguageHighlighter.Session.
/// init`) can consult it without an `await` and without paying the
/// actor's reentrancy budget. The lock guards mutation; reads are
/// snapshot copies. Audit D1.
public final class GrammarRegistry: Sendable {
    /// Process-wide instance used by `SyntaxArtifactsCache`. ADR 8
    /// extension hosts can register additional languages by calling
    /// `GrammarRegistry.shared.register(…)` at startup; the cache
    /// consults the shared registry first and only falls back to
    /// `BundledLanguageManifest` for unregistered names.
    public static let shared = GrammarRegistry()

    private struct State: Sendable {
        /// Keyed by file extension (`.swift`, `.rb`, …) for the hot
        /// `entry(forExtension:)` / `entry(forFilename:)` paths.
        var entries: [String: LanguageEntry] = [:]
        /// Mirror of `entries` keyed by language name. Maintained
        /// alongside `entries` in `register(_:)` so
        /// `entry(forLanguage:)` is O(1) instead of a values walk —
        /// matters at scale once ADR 8 extensions register hundreds of
        /// languages. Audit B.7/E2.
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

    /// Register a language entry. The extensions are stored verbatim;
    /// `entry(forExtension:)` normalises the incoming query so a
    /// caller may register either `".swift"` or `"swift"`.
    public func register(_ entry: LanguageEntry) {
        state.withLock { state in
            for ext in entry.extensions {
                state.entries[ext] = entry
            }
            state.entriesByLanguage[entry.name] = entry
        }
    }

    /// Load entries from a `languages.json` file. Format mirrors
    /// `BundledLanguageManifest` (`name`, `extensions`, `path`).
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
            // Audit C.5/F4 — reject path-traversal payloads in the
            // attacker-controllable `path` field of an extension
            // manifest. Without this guard, a malicious
            // `languages.json` could set `"path": "../../../etc"` and
            // `grammar(for:grammarsPath:)` would read arbitrary files
            // outside the bundled-grammar root. Allow only a single
            // safe-name token; reject `..`, `/`, leading `~`, and
            // anything that contains non-`[A-Za-z0-9_-]` characters.
            guard Self.isSafePathToken(path) else { continue }
            register(LanguageEntry(name: name, extensions: extensions, path: path))
        }
    }

    private static func isSafePathToken(_ value: String) -> Bool {
        guard !value.isEmpty,
            !value.hasPrefix("~"),
            !value.contains(".."),
            !value.contains("/"),
            !value.contains("\\")
        else { return false }
        return value.allSatisfy { ch in
            ch.isASCII
                && (ch.isLetter || ch.isNumber || ch == "_" || ch == "-" || ch == ".")
        }
    }

    /// Find the language entry for a file extension.
    public func entry(forExtension ext: String) -> LanguageEntry? {
        let normalized = ext.hasPrefix(".") ? ext : ".\(ext)"
        return state.withLock { $0.entries[normalized] }
    }

    /// Find the language entry by its registered name. Used by
    /// `SyntaxArtifactsCache.loadArtifacts` as the primary dispatch
    /// path; `BundledLanguageManifest` is the fallback for languages
    /// not registered at runtime.
    public func entry(forLanguage languageName: String) -> LanguageEntry? {
        // O(1) lookup via the language-keyed mirror (audit B.7/E2).
        state.withLock { $0.entriesByLanguage[languageName] }
    }

    /// Find the language entry for a given filename by extracting the
    /// file extension. Mirrors `BundledLanguageManifest.entry(forFilename:)`
    /// so `LanguageHighlighter.detectLanguage(for:)` can consult the
    /// runtime registry before falling back to bundled. Without this,
    /// ADR 8 extension hosts that register additional languages cannot
    /// get their language detected on file open (audit F10).
    public func entry(forFilename filename: String) -> LanguageEntry? {
        let ext = (filename as NSString).pathExtension.lowercased()
        guard !ext.isEmpty else { return nil }
        return entry(forExtension: ext)
    }

    /// Load and cache a grammar definition for a language. Audit B.6 —
    /// resolves the entry via the runtime registry first, falling back
    /// to `BundledLanguageManifest` so `LanguageHighlighter.SyntaxArtifactsCache`
    /// can route every grammar load through this method without
    /// pre-seeding the registry with the bundled set.
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

// MARK: - Bundled entry bridge

extension GrammarRegistry.LanguageEntry {
    /// Wraps a `BundledLanguageEntry` for cases where the bundled
    /// manifest is the fallback resolver — `SyntaxArtifactsCache` uses
    /// this to convert a bundled entry into the shape it would have
    /// found in the runtime registry.
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

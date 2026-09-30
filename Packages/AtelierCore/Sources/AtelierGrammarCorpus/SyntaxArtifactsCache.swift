public import AtelierGrammar
public import AtelierParser
public import AtelierQuery
import AtelierScanners
public import AtelierSyntaxModel
public import Foundation
import Synchronization

/// What highlighting a language from its grammar needs: its compiled tables, its highlight query with the role of
/// each capture, and the external scanner its grammar calls for.
public struct SyntaxArtifacts: Sendable {
    public let parseTable: ParseTable
    public let lexTable: LexTable
    public let productions: [ProductionRule]
    public let query: Query
    /// The role of each of `query`'s capture names, resolved once per language.
    public let roles: CaptureRoles
    /// Whether the grammar needs an external scanner that is not bundled; its tables are then empty.
    public let needsExternalScanner: Bool
    public let scannerType: (any GrammarExternalScanner.Type)?
    /// The grammar's identity: its language, the hash of its `grammar.json` and the compiler's format version
    /// (``GrammarRegistry/grammarKey(for:grammarsPath:)``).
    public let grammarKey: String

    init(
        parseTable: ParseTable, lexTable: LexTable, productions: [ProductionRule], query: Query,
        needsExternalScanner: Bool, scannerType: (any GrammarExternalScanner.Type)?, grammarKey: String
    ) {
        self.parseTable = parseTable
        self.lexTable = lexTable
        self.productions = productions
        self.query = query
        roles = CaptureRoles(captureNames: query.captureNames)
        self.needsExternalScanner = needsExternalScanner
        self.scannerType = scannerType
        self.grammarKey = grammarKey
    }
}

/// Each language's `SyntaxArtifacts`, loaded through a `GrammarRegistry` from a grammars directory; a language whose
/// artifacts could not load is remembered as such.
///
/// Loads run one language at a time, in the order they were asked for: a table load holds tens to hundreds of
/// megabytes while it decodes or compiles (C++ peaks near 500 MB), and several at once went past a gigabyte (design
/// note PERF-11, section 4.2).
///
/// Without ``Limits`` every language loaded stays for the cache's lifetime. With them, a language whose compiled
/// tables are larger than ``Limits/maxTableBytes`` is never kept, and the loaded tables are held to
/// ``Limits/budgetBytes``: past it, the language used least recently goes first, unless a caller holds it pinned
/// (``pin(_:)``). A table's size is its disk cache file's, which a `stat(2)` reads before anything is decoded, and
/// which the tables' memory follows: they hold 4.3 to 6.5 times it once loaded.
public final class SyntaxArtifactsCache: Sendable {
    /// How much of the loaded tables a cache keeps, in bytes of their disk cache files.
    public struct Limits: Sendable, Equatable {
        /// The largest table the cache loads; a larger one is left on disk, and its language stays unloaded.
        public var maxTableBytes: Int
        /// The tables the cache keeps loaded, pinned ones apart, before it unloads the least recently used.
        public var budgetBytes: Int

        public init(maxTableBytes: Int, budgetBytes: Int) {
            self.maxTableBytes = maxTableBytes
            self.budgetBytes = budgetBytes
        }
    }

    /// What the cache knows of a language.
    private enum Entry {
        case loaded(Loaded)
        /// No artifacts: no entry, no query, or a grammar that does not load or compile.
        case unavailable
        /// Tables larger than ``Limits/maxTableBytes``, left on disk.
        case oversized(tableBytes: Int)
    }

    private struct Loaded {
        var artifacts: SyntaxArtifacts
        /// The size of the tables' disk cache file; zero without limits, which never measure it.
        var tableBytes: Int
        /// When the language was last used, in the cache's own count of uses.
        var lastUse: UInt64
        /// How many callers hold it pinned.
        var pins: Int
    }

    private struct State {
        var entries: [String: Entry] = [:]
        var uses: UInt64 = 0
    }

    /// Whether a language is known, and if so, its artifacts.
    private enum Resolution {
        case unknown
        case resolved(SyntaxArtifacts?)
    }

    /// What loading a language gave.
    private enum Outcome {
        case loaded(SyntaxArtifacts, tableBytes: Int)
        case unavailable
        case oversized(tableBytes: Int)
    }

    private let state = Mutex(State())
    private let registry: GrammarRegistry
    /// The directory each entry's `path` names a subdirectory of; nil when there is none, and nothing loads.
    private let grammarsDirectory: URL?
    /// Whose turn it is to load.
    private let turns: LoadTurns
    /// How much of the tables the cache keeps; nil keeps every table it loads.
    public let limits: Limits?

    /// - Parameters:
    ///   - registry: Where each language's entry, grammar and compiled tables come from.
    ///   - grammarsDirectory: The directory the entries' paths name subdirectories of.
    ///   - limits: How much of the tables the cache keeps; nil keeps every table it loads.
    public convenience init(registry: GrammarRegistry, grammarsDirectory: URL?, limits: Limits? = nil) {
        self.init(registry: registry, grammarsDirectory: grammarsDirectory, limits: limits, onQueued: { _ in })
    }

    /// - Parameters:
    ///   - registry: Where each language's entry, grammar and compiled tables come from.
    ///   - grammarsDirectory: The directory the entries' paths name subdirectories of.
    ///   - limits: How much of the tables the cache keeps; nil keeps every table it loads.
    ///   - onQueued: Called with a language whose load waits for another's to end; tests watch it.
    init(
        registry: GrammarRegistry, grammarsDirectory: URL?, limits: Limits? = nil,
        onQueued: @escaping @Sendable (String) -> Void
    ) {
        self.registry = registry
        self.grammarsDirectory = grammarsDirectory
        self.limits = limits
        turns = LoadTurns(onQueued: onQueued)
    }

    /// `language`'s artifacts when they are loaded.
    public func artifacts(for language: String) -> SyntaxArtifacts? {
        state.withLock { state in
            guard case .loaded(let loaded) = state.entries[language] else { return nil }
            return loaded.artifacts
        }
    }

    /// Whether `language`'s tables are larger than ``Limits/maxTableBytes``, so the cache leaves them on disk.
    public func isOversized(_ language: String) -> Bool {
        state.withLock { state in
            guard case .oversized = state.entries[language] else { return false }
            return true
        }
    }

    /// Whether `language`'s tables can load under the limits, as far as the cache knows without compiling them: false
    /// once a load found them unavailable or larger than ``Limits/maxTableBytes``, or when the disk cache holds them
    /// that large, which it records then; true otherwise, and always without limits. A table the disk cache does not
    /// hold yet is known only once compiled, which happens once per grammar version: its stored size answers every
    /// later ask. A grammar tier asks before it starts a job, so a language over the limit starts none.
    /// - Complexity: O(1) once answered for `language`; a file's size and the grammar's key otherwise.
    public func admits(_ language: String) -> Bool {
        guard let limits else { return true }
        let known: Bool? = state.withLock { state in
            switch state.entries[language] {
                case .loaded?: true
                case .oversized?, .unavailable?: false
                case nil: nil
            }
        }
        if let known { return known }
        guard let entry = registry.resolvedEntry(forLanguage: language), let grammarsDirectory,
            let stored = try? registry.cachedTableBytes(for: entry.name, grammarsPath: grammarsDirectory.path),
            stored > limits.maxTableBytes
        else { return true }
        state.withLock { state in
            if state.entries[language] == nil { state.entries[language] = .oversized(tableBytes: stored) }
        }
        return false
    }

    /// The languages whose tables are loaded.
    public var loadedLanguages: Set<String> {
        state.withLock { state in
            Set(
                state.entries.compactMap { language, entry in
                    guard case .loaded = entry else { return nil }
                    return language
                })
        }
    }

    /// The disk cache size of the tables loaded, pinned ones included; zero without limits.
    public var loadedTableBytes: Int {
        state.withLock { Self.loadedBytes(in: $0) }
    }

    /// Loads `language`'s artifacts unless they are loaded or known not to load, once every load asked for before
    /// it has ended, compiling its tables when the disk cache has none.
    public func loadIfNeeded(for language: String) async {
        _ = await resolve(language, pinning: false, cachedOnly: false)
    }

    /// `language`'s artifacts, loaded as ``loadIfNeeded(for:)`` loads them, and pinned: the cache does not unload them
    /// until a matching ``unpin(_:)``. Nil when they do not load, and then nothing is pinned.
    public func pin(_ language: String) async -> SyntaxArtifacts? {
        await resolve(language, pinning: true, cachedOnly: false)
    }

    /// Releases a pin ``pin(_:)`` took, and unloads what the budget no longer holds.
    public func unpin(_ language: String) {
        let evicted = state.withLock { state -> [String] in
            if case .loaded(var loaded) = state.entries[language], loaded.pins > 0 {
                loaded.pins -= 1
                state.entries[language] = .loaded(loaded)
            }
            return evict(&state)
        }
        forget(evicted)
    }

    /// Loads the artifacts of each of `languages` whose tables are already on disk, one at a time, never starting a
    /// compile, and returns the languages whose artifacts are then loaded.
    public func prewarm<S: Sequence>(languages: S) async -> Set<String> where S.Element == String {
        let uniqueLanguages = Set(languages)
        for language in uniqueLanguages.sorted() {
            _ = await resolve(language, pinning: false, cachedOnly: true)
        }
        return uniqueLanguages.intersection(loadedLanguages)
    }

    /// `language`'s artifacts: known already, or loaded in its turn. A cached-only load that finds no tables on disk
    /// leaves the language unknown, so a later load compiles them.
    private func resolve(_ language: String, pinning: Bool, cachedOnly: Bool) async -> SyntaxArtifacts? {
        if case .resolved(let artifacts) = use(language, pinning: pinning) { return artifacts }
        await turns.acquire(for: language)
        defer { turns.release() }
        // A load that waited may find the language loaded by the one before it.
        if case .resolved(let artifacts) = use(language, pinning: pinning) { return artifacts }
        let outcome = await loadArtifacts(for: language, cachedOnly: cachedOnly)
        let (artifacts, evicted) = state.withLock { state -> (SyntaxArtifacts?, [String]) in
            state.uses += 1
            let artifacts: SyntaxArtifacts?
            switch outcome {
                case .loaded(let loaded, let tableBytes):
                    state.entries[language] = .loaded(
                        Loaded(artifacts: loaded, tableBytes: tableBytes, lastUse: state.uses, pins: pinning ? 1 : 0))
                    artifacts = loaded
                case .oversized(let tableBytes):
                    state.entries[language] = .oversized(tableBytes: tableBytes)
                    artifacts = nil
                case .unavailable:
                    if !cachedOnly { state.entries[language] = .unavailable }
                    artifacts = nil
            }
            return (artifacts, evict(&state))
        }
        forget(evicted)
        return artifacts
    }

    /// What the cache knows of `language`, counting a use of loaded artifacts and taking a pin when `pinning`.
    private func use(_ language: String, pinning: Bool) -> Resolution {
        state.withLock { state in
            switch state.entries[language] {
                case nil:
                    return .unknown
                case .unavailable, .oversized:
                    return .resolved(nil)
                case .loaded(var loaded):
                    state.uses += 1
                    loaded.lastUse = state.uses
                    if pinning { loaded.pins += 1 }
                    state.entries[language] = .loaded(loaded)
                    return .resolved(loaded.artifacts)
            }
        }
    }

    private static func loadedBytes(in state: State) -> Int {
        state.entries.values.reduce(0) { total, entry in
            guard case .loaded(let loaded) = entry else { return total }
            return total + loaded.tableBytes
        }
    }

    /// Unloads the least recently used languages that no one pins until the loaded tables fit the budget, and
    /// returns them; nothing without limits.
    private func evict(_ state: inout State) -> [String] {
        guard let limits else { return [] }
        var evicted: [String] = []
        var total = Self.loadedBytes(in: state)
        while total > limits.budgetBytes {
            let oldest = state.entries
                .compactMap { language, entry -> (String, Loaded)? in
                    guard case .loaded(let loaded) = entry, loaded.pins == 0 else { return nil }
                    return (language, loaded)
                }
                .min { $0.1.lastUse < $1.1.lastUse }
            guard let (language, loaded) = oldest else { break }
            state.entries[language] = nil
            total -= loaded.tableBytes
            evicted.append(language)
        }
        return evicted
    }

    /// Lets the registry free the tables of `languages`, which the cache no longer holds.
    private func forget(_ languages: [String]) {
        for language in languages {
            guard let name = registry.resolvedEntry(forLanguage: language)?.name else { continue }
            registry.forgetCompiledTables(for: name)
        }
    }

    /// Loads `language`'s artifacts: its query, its grammar and its tables, from the disk cache or, unless
    /// `cachedOnly`, compiled. With limits, tables whose disk cache file is larger than ``Limits/maxTableBytes`` are
    /// never decoded; tables compiled now are measured once stored, and dropped when too large.
    private func loadArtifacts(for language: String, cachedOnly: Bool) async -> Outcome {
        // A runtime registration wins over the bundled manifest; either way `entry.path` names a directory of
        // `grammarsDirectory`.
        guard let entry = registry.resolvedEntry(forLanguage: language), let grammarsDirectory else {
            return .unavailable
        }

        let queryURL = grammarsDirectory.appending(path: entry.path).appending(path: "highlights.scm")
        guard let querySource = try? String(contentsOf: queryURL, encoding: .utf8),
            let query = try? QueryParser.parse(querySource)
        else {
            return .unavailable
        }

        // Loaded through the registry, whose disk cache spares a relaunch the parse-table compile.
        let grammarsPath = grammarsDirectory.path
        let grammar: GrammarDefinition
        do {
            grammar = try registry.grammar(for: entry.name, grammarsPath: grammarsPath)
        } catch {
            return .unavailable
        }

        let grammarKey: String
        do {
            grammarKey = try registry.grammarKey(for: entry.name, grammarsPath: grammarsPath)
        } catch {
            return .unavailable
        }
        let needsExternals = !grammar.externals.isEmpty
        let scannerType = BundledScanners.byGrammarName[grammar.name]

        // Without its external scanners a grammar can't parse, so a session never reads its table, and compiling one
        // (bash's especially) can take gigabytes: store empty tables and keep the flag for capability reporting.
        if needsExternals && scannerType == nil {
            if cachedOnly { return .unavailable }
            let empty = SyntaxArtifacts(
                parseTable: ParseTable(
                    stateCount: 0, symbols: [], terminals: [], nonTerminals: [],
                    actions: [], gotos: []),
                lexTable: LexTable(),
                productions: [],
                query: query,
                needsExternalScanner: true,
                scannerType: nil,
                grammarKey: grammarKey
            )
            return .loaded(empty, tableBytes: 0)
        }

        if let limits, let stored = try? registry.cachedTableBytes(for: entry.name, grammarsPath: grammarsPath),
            stored > limits.maxTableBytes
        {
            return .oversized(tableBytes: stored)
        }

        let compiled: ParseTableCompiler.CompilationResult
        do {
            if cachedOnly {
                guard let stored = try registry.cachedResult(for: entry.name, grammarsPath: grammarsPath) else {
                    return .unavailable
                }
                compiled = stored
            } else {
                compiled = try await registry.compiledResult(for: entry.name, grammarsPath: grammarsPath)
            }
        } catch {
            return .unavailable
        }

        var tableBytes = 0
        if let limits {
            // Measured as stored; a cache that could not store them measures them encoded.
            tableBytes =
                (try? registry.cachedTableBytes(for: entry.name, grammarsPath: grammarsPath))
                ?? (try? GrammarRegistry.encodeCompiledTables(compiled).count) ?? Int.max
            guard tableBytes <= limits.maxTableBytes else {
                registry.forgetCompiledTables(for: entry.name)
                return .oversized(tableBytes: tableBytes)
            }
        }
        let artifacts = SyntaxArtifacts(
            parseTable: compiled.parseTable,
            lexTable: compiled.lexTable,
            productions: compiled.productions,
            query: query,
            needsExternalScanner: false,
            scannerType: scannerType,
            grammarKey: grammarKey
        )
        return .loaded(artifacts, tableBytes: tableBytes)
    }
}

/// One load at a time: a caller takes the turn, or waits for it in the order it asked, and hands it on when done.
private final class LoadTurns: Sendable {
    private struct State {
        var isTaken = false
        var waiting: [CheckedContinuation<Void, Never>] = []
    }

    private let state = Mutex(State())
    private let onQueued: @Sendable (String) -> Void

    init(onQueued: @escaping @Sendable (String) -> Void) {
        self.onQueued = onQueued
    }

    /// Returns once the caller holds the turn. A cancelled caller still waits for its turn: the load it guards is
    /// shared work that other callers wait on too.
    func acquire(for language: String) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let takesTurn = state.withLock { state in
                if state.isTaken {
                    state.waiting.append(continuation)
                    return false
                }
                state.isTaken = true
                return true
            }
            if takesTurn {
                continuation.resume()
            } else {
                onQueued(language)
            }
        }
    }

    /// Hands the turn to the caller that has waited longest, or frees it.
    func release() {
        let next = state.withLock { state -> CheckedContinuation<Void, Never>? in
            guard !state.waiting.isEmpty else {
                state.isTaken = false
                return nil
            }
            return state.waiting.removeFirst()
        }
        next?.resume()
    }
}

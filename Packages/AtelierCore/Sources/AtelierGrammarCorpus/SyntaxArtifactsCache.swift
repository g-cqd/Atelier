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

/// Each language's `SyntaxArtifacts`, loaded once through a `GrammarRegistry` from a grammars directory, and kept for
/// the cache's lifetime; a language whose artifacts could not load is remembered as such.
///
/// Loads run one language at a time, in the order they were asked for: a table load holds tens to hundreds of
/// megabytes while it decodes or compiles (C++ peaks near 500 MB), and several at once went past a gigabyte (design
/// note PERF-11, section 4.2).
public final class SyntaxArtifactsCache: Sendable {
    private let storage = Mutex([String: SyntaxArtifacts?]())
    private let registry: GrammarRegistry
    /// The directory each entry's `path` names a subdirectory of; nil when there is none, and nothing loads.
    private let grammarsDirectory: URL?
    /// Whose turn it is to load.
    private let turns: LoadTurns

    public convenience init(registry: GrammarRegistry, grammarsDirectory: URL?) {
        self.init(registry: registry, grammarsDirectory: grammarsDirectory, onQueued: { _ in })
    }

    /// - Parameters:
    ///   - registry: Where each language's entry, grammar and compiled tables come from.
    ///   - grammarsDirectory: The directory the entries' paths name subdirectories of.
    ///   - onQueued: Called with a language whose load waits for another's to end; tests watch it.
    init(registry: GrammarRegistry, grammarsDirectory: URL?, onQueued: @escaping @Sendable (String) -> Void) {
        self.registry = registry
        self.grammarsDirectory = grammarsDirectory
        turns = LoadTurns(onQueued: onQueued)
    }

    public func artifacts(for language: String) -> SyntaxArtifacts? {
        storage.withLock { $0[language] } ?? nil
    }

    /// Loads `language`'s artifacts unless they are loaded or known not to load, once every load asked for before
    /// it has ended, compiling its tables when the disk cache has none.
    public func loadIfNeeded(for language: String) async {
        guard !isResolved(language) else { return }
        await turns.acquire(for: language)
        defer { turns.release() }
        // A load that waited may find the language loaded by the one before it.
        guard !isResolved(language) else { return }
        let loaded = await loadArtifacts(for: language, cachedOnly: false)
        storage.withLock { cache in
            guard !cache.keys.contains(language) else { return }
            cache[language] = loaded
        }
    }

    /// Whether `language` is loaded or known not to load.
    private func isResolved(_ language: String) -> Bool {
        storage.withLock { $0[language] != nil }
    }

    /// Loads the artifacts of each of `languages` whose tables are already on disk, one at a time, never starting a
    /// compile, and returns the languages whose artifacts are then loaded.
    public func prewarm<S: Sequence>(languages: S) async -> Set<String> where S.Element == String {
        let uniqueLanguages = Set(languages)
        for language in uniqueLanguages.sorted() where !isResolved(language) {
            await turns.acquire(for: language)
            defer { turns.release() }
            guard !isResolved(language),
                let loadedArtifacts = await loadArtifacts(for: language, cachedOnly: true)
            else { continue }
            storage.withLock { cache in
                guard !cache.keys.contains(language) else { return }
                cache[language] = loadedArtifacts
            }
        }

        return Set(
            uniqueLanguages.filter { language in
                storage.withLock {
                    if case .some(.some(_)) = $0[language] {
                        return true
                    }
                    return false
                }
            })
    }

    private func loadArtifacts(for language: String, cachedOnly: Bool) async -> SyntaxArtifacts? {
        // A runtime registration wins over the bundled manifest; either way `entry.path` names a directory of
        // `grammarsDirectory`.
        guard let entry = registry.resolvedEntry(forLanguage: language), let grammarsDirectory else {
            return nil
        }

        let queryURL = grammarsDirectory.appending(path: entry.path).appending(path: "highlights.scm")
        guard let querySource = try? String(contentsOf: queryURL, encoding: .utf8),
            let query = try? QueryParser.parse(querySource)
        else {
            return nil
        }

        // Loaded through the registry, whose disk cache spares a relaunch the parse-table compile.
        let grammarsPath = grammarsDirectory.path
        let grammar: GrammarDefinition
        do {
            grammar = try registry.grammar(for: entry.name, grammarsPath: grammarsPath)
        } catch {
            return nil
        }

        let grammarKey: String
        do {
            grammarKey = try registry.grammarKey(for: entry.name, grammarsPath: grammarsPath)
        } catch {
            return nil
        }
        let needsExternals = !grammar.externals.isEmpty
        let scannerType = BundledScanners.byGrammarName[grammar.name]

        // Without its external scanners a grammar can't parse, so a session never reads its table, and compiling one
        // (bash's especially) can take gigabytes: store empty tables and keep the flag for capability reporting.
        if needsExternals && scannerType == nil {
            if cachedOnly { return nil }
            return SyntaxArtifacts(
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
        }

        let compiled: ParseTableCompiler.CompilationResult
        do {
            if cachedOnly {
                guard let stored = try registry.cachedResult(for: entry.name, grammarsPath: grammarsPath) else {
                    return nil
                }
                compiled = stored
            } else {
                compiled = try await registry.compiledResult(for: entry.name, grammarsPath: grammarsPath)
            }
        } catch {
            return nil
        }

        return SyntaxArtifacts(
            parseTable: compiled.parseTable,
            lexTable: compiled.lexTable,
            productions: compiled.productions,
            query: query,
            needsExternalScanner: false,
            scannerType: scannerType,
            grammarKey: grammarKey
        )
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

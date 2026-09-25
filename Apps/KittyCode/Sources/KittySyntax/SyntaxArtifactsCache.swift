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

    init(
        parseTable: ParseTable, lexTable: LexTable, productions: [ProductionRule], query: Query,
        needsExternalScanner: Bool, scannerType: (any GrammarExternalScanner.Type)?
    ) {
        self.parseTable = parseTable
        self.lexTable = lexTable
        self.productions = productions
        self.query = query
        roles = CaptureRoles(captureNames: query.captureNames)
        self.needsExternalScanner = needsExternalScanner
        self.scannerType = scannerType
    }
}

/// Each language's `SyntaxArtifacts`, loaded once through a `GrammarRegistry` from a grammars directory, and kept for
/// the cache's lifetime; a language whose artifacts could not load is remembered as such.
public final class SyntaxArtifactsCache: Sendable {
    private let storage = Mutex([String: SyntaxArtifacts?]())
    private let registry: GrammarRegistry
    /// The directory each entry's `path` names a subdirectory of; nil when there is none, and nothing loads.
    private let grammarsDirectory: URL?

    public init(registry: GrammarRegistry, grammarsDirectory: URL?) {
        self.registry = registry
        self.grammarsDirectory = grammarsDirectory
    }

    public func artifacts(for language: String) -> SyntaxArtifacts? {
        storage.withLock { $0[language] } ?? nil
    }

    public func loadIfNeeded(for language: String) async {
        let alreadyCached: Bool = storage.withLock { $0[language] != nil }
        guard !alreadyCached else { return }

        let loaded = await loadArtifacts(for: language, cachedOnly: false)
        storage.withLock { cache in
            guard !cache.keys.contains(language) else { return }
            cache[language] = loaded
        }
    }

    /// Loads the artifacts of each of `languages` whose tables are already on disk, never starting a compile, and
    /// returns the languages whose artifacts are then loaded.
    public func prewarm<S: Sequence>(languages: S) async -> Set<String> where S.Element == String {
        let uniqueLanguages = Set(languages)
        let uncachedLanguages = uniqueLanguages.filter { language in
            storage.withLock { !$0.keys.contains(language) }
        }

        await withTaskGroup(of: (String, SyntaxArtifacts?).self) { group in
            for language in uncachedLanguages {
                group.addTask {
                    (language, await self.loadArtifacts(for: language, cachedOnly: true))
                }
            }

            for await (language, loadedArtifacts) in group {
                guard let loadedArtifacts else { continue }
                storage.withLock { cache in
                    guard !cache.keys.contains(language) else { return }
                    cache[language] = loadedArtifacts
                }
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
                scannerType: nil
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
            scannerType: scannerType
        )
    }
}

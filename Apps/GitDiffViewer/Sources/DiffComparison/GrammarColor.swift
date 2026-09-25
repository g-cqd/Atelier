package import AemiRuntime
package import AtelierGrammarCorpus
package import AtelierHighlighting
package import AtelierSyntaxModel
import DiffRendering
package import Foundation
import Synchronization
import os

/// What grammar colour needs app-wide (PERF-11 step 5): the bundled grammars' tables, loaded lazily, one grammar at a
/// time and under a memory budget; what each grammar did with the texts it parsed; and the threads parses run on.
/// Every window's grammar tier runs through them.
package final class GrammarColorServices: Sendable {
    /// The largest table grammar colour loads, and the tables it keeps loaded, in bytes of their disk cache files,
    /// which hold 4.3 to 6.5 times less than the tables once loaded (design note PERF-11, section 4.2).
    ///
    /// The limit keeps every table of at most 20 MB: JSON's, TOML's, CSS's, Lua's, HTML's, YAML's, Ruby's (8 MB),
    /// JavaScript's (9.6 MB), Go's (11.4 MB) and Python's (16.7 MB, 78 to 94 MB loaded). Java's (30 MB), C's and
    /// Bash's (45 MB), TypeScript's (49 MB, 322 MB loaded), Rust's and Kotlin's (60 MB) and C++'s (107 MB, 495 MB
    /// loaded) stay on disk until their tables are smaller. The budget holds any two of the tables kept, the two
    /// largest among them, 150 to 210 MB once loaded; a table a parse is using stays however far past it.
    package static let limits = SyntaxArtifactsCache.Limits(maxTableBytes: 20 << 20, budgetBytes: 32 << 20)

    /// How many parses run at once: a quarter of the cores, at least one (design note, section 4.6).
    package static let parseWidth = max(1, ProcessInfo.processInfo.activeProcessorCount / 4)

    package let artifacts: SyntaxArtifactsCache
    package let record: GrammarTierRecord
    /// The threads parses run on; shut down with the app.
    private let pool: BlockingOffloadPool?
    package let tier: GrammarTier

    /// - Parameters:
    ///   - artifacts: The grammars' tables and queries.
    ///   - pool: The threads parses run on; nil parses on the caller's.
    package init(artifacts: SyntaxArtifactsCache, pool: BlockingOffloadPool?) {
        self.artifacts = artifacts
        self.pool = pool
        let record = GrammarTierRecord()
        self.record = record
        tier = GrammarTier(artifacts: artifacts, record: record, pool: pool)
    }

    private static let logger = Logger(subsystem: "fr.gcqd.GitDiffViewer", category: "GrammarColor")

    /// The services over the bundled corpus, with their compiled tables cached in `cacheDirectory`, ``limits`` and a
    /// pool of ``parseWidth`` threads at utility priority; nil, logged, when the corpus is missing from the app.
    package static func bundled(cacheDirectory: URL) -> GrammarColorServices? {
        do {
            let corpus = try GrammarCorpus.bundled()
            let registry = GrammarRegistry(cacheDirectory: cacheDirectory, bundledManifest: try corpus.manifest())
            return GrammarColorServices(
                artifacts: SyntaxArtifactsCache(
                    registry: registry, grammarsDirectory: corpus.grammarsDirectory, limits: limits),
                pool: BlockingOffloadPool(width: parseWidth, qualityOfService: .utility))
        } catch {
            logger.fault("grammar color is off: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// Where the app caches compiled grammar tables: its own directory under the user's caches.
    package static var defaultCacheDirectory: URL {
        let caches =
            FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appending(path: "fr.gcqd.GitDiffViewer/grammar-tables", directoryHint: .isDirectory)
    }

    /// Stops the parse threads, once every parse queued has run.
    package func shutdown() {
        pool?.shutdown()
    }
}

/// Which tiers a window's refinement runs, read by the tiers from any thread: grammar colour for the languages it is
/// on for, once the app's services are attached, and swift-syntax's and the language server's for Swift while the
/// Swift setting is on.
package final class ColorTierGate: Sendable {
    private struct State {
        var services: GrammarColorServices?
        var grammarOff: Set<Language> = []
        var refinesSwift = true
    }

    private let state = Mutex(State())

    package init() {}

    /// The languages grammar colour can be on for: every language with a bundled grammar but Swift, whose grammar
    /// stays off in GitDiffViewer while swift-syntax colours it (D33), sorted by name.
    package static let languages: [Language] = Language.allCases
        .filter { $0 != .swift && GrammarEngine.grammarName(of: $0) != nil }
        .sorted { displayName(of: $0) < displayName(of: $1) }

    /// One of the Settings window's rows: a language by the name the setting stores, and its title.
    package struct SettingRow: Identifiable, Sendable {
        package let id: String
        package let title: String
    }

    /// The Settings window's rows, one per language of ``languages``.
    package static var settingRows: [SettingRow] {
        languages.map { SettingRow(id: $0.name, title: displayName(of: $0)) }
    }

    /// How the Settings window names `language`.
    package static func displayName(of language: Language) -> String {
        switch language {
            case .c: "C"
            case .cpp: "C++"
            case .css: "CSS"
            case .go: "Go"
            case .html: "HTML"
            case .java: "Java"
            case .javascript: "JavaScript"
            case .json: "JSON"
            case .kotlin: "Kotlin"
            case .lua: "Lua"
            case .python: "Python"
            case .ruby: "Ruby"
            case .rust: "Rust"
            case .shell: "Shell"
            case .toml: "TOML"
            case .typescript: "TypeScript"
            case .yaml: "YAML"
            default: language.name
        }
    }

    /// The app's services, once attached.
    package var services: GrammarColorServices? {
        state.withLock { $0.services }
    }

    /// Whether grammar colour runs for `language`.
    package func grammarColors(_ language: Language) -> Bool {
        state.withLock { state in
            state.services != nil && Self.languages.contains(language) && !state.grammarOff.contains(language)
        }
    }

    /// Whether grammar colour runs for any language.
    package var colorsAnyGrammar: Bool {
        state.withLock { state in
            state.services != nil && Self.languages.contains { !state.grammarOff.contains($0) }
        }
    }

    /// Whether Swift sides take swift-syntax's colour, and the language server's.
    package var refinesSwift: Bool {
        state.withLock { $0.refinesSwift }
    }

    /// Sets what the tiers read; true when anything changed.
    @discardableResult
    package func update(
        services: GrammarColorServices?, grammarOff: Set<Language>, refinesSwift: Bool
    ) -> Bool {
        state.withLock { state in
            let changed =
                (state.services !== services) || state.grammarOff != grammarOff || state.refinesSwift != refinesSwift
            state.services = services
            state.grammarOff = grammarOff
            state.refinesSwift = refinesSwift
            return changed
        }
    }
}

/// Grammar colour as a tier of a window's refinement: the app's grammar tier, for the languages the gate has it on
/// for.
package struct GrammarColorTier: AtelierHighlighting.HighlightTier {
    let gate: ColorTierGate

    package init(gate: ColorTierGate) {
        self.gate = gate
    }

    package var layer: HighlightLayer { .structural }
    package var coverage: TierCoverage { .complete }
    package var deadline: Duration? { nil }

    package func supports(_ language: Language) -> Bool {
        gate.grammarColors(language)
    }

    package func run(_ request: TierRequest, emit: (TierUpdate) async -> Void) async throws {
        guard let services = gate.services else { throw TierFailure.failed("grammar color is off") }
        try await services.tier.run(request, emit: emit)
    }
}

/// A Swift tier that runs only while the gate refines Swift, so turning swift-syntax's colour off leaves Swift sides
/// the lexer's while other languages keep their grammar's.
package struct SwiftColorTier: AtelierHighlighting.HighlightTier {
    let base: any AtelierHighlighting.HighlightTier
    let gate: ColorTierGate

    package init(_ base: any AtelierHighlighting.HighlightTier, gate: ColorTierGate) {
        self.base = base
        self.gate = gate
    }

    package var layer: HighlightLayer { base.layer }
    package var coverage: TierCoverage { base.coverage }
    package var deadline: Duration? { base.deadline }

    package func supports(_ language: Language) -> Bool {
        gate.refinesSwift && base.supports(language)
    }

    package func run(_ request: TierRequest, emit: (TierUpdate) async -> Void) async throws {
        try await base.run(request, emit: emit)
    }
}

extension DiffViewerModel {
    /// The tiers a window's refinement runs: swift-syntax's and the language server's on Swift sides while the gate
    /// refines Swift, and the grammar's on the languages the gate has grammar colour on for.
    static func tiers(
        store: SyntaxFactsStore, semantic: SemanticColorSource, gate: ColorTierGate
    ) -> [any AtelierHighlighting.HighlightTier] {
        DiffDecorations.tiers(store: store).map { SwiftColorTier($0, gate: gate) }
            + [SwiftColorTier(semantic.tier(store: store), gate: gate), GrammarColorTier(gate: gate)]
    }

    /// Gives this window's grammar tier the app's services; the displayed sides whose language it now colours refine.
    package func attachGrammarColor(_ services: GrammarColorServices?) {
        attachedGrammarColor = services
        followColorSettings()
    }

    /// Follows the colour settings: which languages take their grammar's colour (D34), and whether Swift takes
    /// swift-syntax's. A change refines the displayed sides afresh through the refinement's own reset, and the
    /// refinement runs while any of them is on.
    func followColorSettings() {
        let grammarOff = Set(settings.grammarColorOff.compactMap(Language.init(name:)))
        let changed = colorGate.update(
            services: attachedGrammarColor, grammarOff: grammarOff, refinesSwift: settings.refinesSwiftColor)
        if changed, pipeline.refinesSwiftColor { pipeline.refinesSwiftColor = false }
        pipeline.refinesSwiftColor = settings.refinesSwiftColor || colorGate.colorsAnyGrammar
    }
}

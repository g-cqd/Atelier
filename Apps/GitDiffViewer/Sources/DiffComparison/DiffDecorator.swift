package import AtelierHighlighting
package import DiffCore
package import DiffRendering
package import Foundation
import Observation

/// What the stages after the text found for the files the pipeline publishes (PERF-09 stages 1 and 2): each displayed
/// side's colour, from the lexer and swift-syntax through the core tier job (PERF-11), and each displayed file's
/// intraline emphasis and moved lines, as `DiffDecorations` per published text.
///
/// A side is coloured once per content: its blob id, which is a content hash on every kind of source, or, for a side
/// without one, the preparation that read it. Both sides of a file with one blob share one result, and a file shown
/// again, relaid out or reloaded unchanged, takes its colour from here at once. A file's emphasis and moved lines are
/// found once per preparation. Each lands in chunks, the visible lines first.
@MainActor
@Observable
package final class DiffDecorator {
    /// What one side's colour is kept under.
    package enum ContentKey: Hashable, Sendable {
        case blob(String, Language)
        /// A side without a blob id, which only its own preparation can vouch for.
        case preparation(UUID, RenderedSide)
    }

    /// What a stage was started for: the pipeline's generation, and the rendered file it was asked for.
    struct Stamp {
        let generation: Int
        let fileID: RenderedDiff.ID
    }

    /// A file's emphasis and moved lines as they land: each side's emphasis by source line.
    struct Marks {
        var old: [Int: [Range<Int>]] = [:]
        var new: [Int: [Range<Int>]] = [:]
        var moved: MovedLines?
        var version = 0
    }

    /// How many sides' colours, and files' marks, are kept past those a published file shows, the oldest going first.
    /// What a published file shows is never dropped: nothing would colour it again until a pane showed the file anew,
    /// and a card that stays on screen does not; in a long card list, colouring one card dropped its neighbours'.
    package static let cacheCapacity = 64

    /// The decorations of every published text that has any, by ``RenderedText/id``: what a pane draws.
    package private(set) var byText: [UUID: DiffDecorations] = [:]
    /// Whether displayed sides get the colour of the tiers after the lexer, swift-syntax's and a language server's; off,
    /// only the lexer colours them.
    @ObservationIgnored package internal(set) var refinesSwiftColor = true
    /// How many colour jobs started, one per side, and marks jobs, one per file; for tests and traces.
    @ObservationIgnored package private(set) var started = 0
    @ObservationIgnored package private(set) var marksStarted = 0
    /// The tiers each displayed side may run, and the clock the stages' deadlines are measured on.
    @ObservationIgnored let tiers: [any AtelierHighlighting.HighlightTier]
    @ObservationIgnored let clock: any Clock<Duration>
    /// Where a Swift side's scopes are read from the parse its colour made; nil finds every side's from its braces.
    @ObservationIgnored let store: SyntaxFactsStore?
    /// Where panes report the rows they show, which the stages decorate first.
    @ObservationIgnored package let viewport = DecorationViewport()
    @ObservationIgnored private var colors: [ContentKey: (tokens: LayeredLineTokens, version: Int)] = [:]
    @ObservationIgnored private var colorOrder: [ContentKey] = []
    @ObservationIgnored private var colorJobs: [ContentKey: Task<Void, Never>] = [:]
    /// The sides whose job ran to its end, every tier finished or failed: they are not coloured again.
    @ObservationIgnored private var endedColors: Set<ContentKey> = []
    @ObservationIgnored private var marks: [UUID: Marks] = [:]
    @ObservationIgnored private var marksOrder: [UUID] = []
    @ObservationIgnored private var marksJobs: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var endedMarks: Set<UUID> = []
    /// Each side's scopes, by its colour key, as they land, with the version they landed at (DIFF-03).
    @ObservationIgnored private var scopes: [ContentKey: (lines: ScopeLines, version: Int)] = [:]
    @ObservationIgnored private var scopeOrder: [ContentKey] = []
    @ObservationIgnored private var scopeJobs: [ContentKey: Task<Void, Never>] = [:]
    @ObservationIgnored private var endedScopes: Set<ContentKey> = []
    /// The rendered files a pane reported on screen, kept while they stay published, so a change of setting decorates
    /// what shows.
    @ObservationIgnored private var displayed: Set<RenderedDiff.ID> = []
    /// The colour keys and preparations of the files last published, whose colours, scopes and marks are kept.
    @ObservationIgnored private var published: (keys: Set<ContentKey>, preparations: Set<UUID>) = ([], [])
    /// Each published file's decorations with what they were composed from, so a file's value, and so its panes,
    /// change only when something it draws lands.
    @ObservationIgnored private var composed: [Composition: (inputs: Inputs, decorations: DiffDecorations)] = [:]
    @ObservationIgnored private var lastVersion = 0

    /// A published file's parts: its preparation and its two sides' colour keys.
    struct Composition: Hashable {
        let preparation: UUID
        let old: ContentKey?
        let new: ContentKey?
    }

    /// The versions of what a file's decorations are composed from.
    private struct Inputs: Equatable {
        let old: Int?
        let new: Int?
        let marks: Int?
        let oldScopes: Int?
        let newScopes: Int?
    }

    /// - Parameters:
    ///   - tiers: The tiers each displayed side may run: those of a language that supports it, those after the lexer
    ///     only while ``refinesSwiftColor`` holds.
    ///   - clock: The clock the stages' deadlines are measured on.
    ///   - store: Where a Swift side's scopes are read from the parse its colour tier made; nil finds every side's
    ///     scopes from its braces.
    package init(
        tiers: [any AtelierHighlighting.HighlightTier] = DiffDecorations.tiers(),
        clock: any Clock<Duration> = ContinuousClock(), store: SyntaxFactsStore? = nil
    ) {
        self.tiers = tiers
        self.clock = clock
        self.store = store
    }

    /// The tiers a side of `language` runs now.
    func activeTiers(for language: Language) -> [any AtelierHighlighting.HighlightTier] {
        tiers.filter { $0.supports(language) && (refinesSwiftColor || $0.layer == .lexical) }
    }

    func nextVersion() -> Int {
        lastVersion += 1
        return lastVersion
    }

    /// Stops every colour job and forgets every colour; emphasis and moved lines stay.
    func resetColors() {
        for task in colorJobs.values { task.cancel() }
        colorJobs = [:]
        colors = [:]
        colorOrder = []
        endedColors = []
    }

    /// Stops the jobs whose content no published file shows any more.
    func cancel(keepingColors keys: Set<ContentKey>, marks preparations: Set<UUID>) {
        for (key, task) in colorJobs where !keys.contains(key) {
            task.cancel()
            colorJobs[key] = nil
        }
        for (key, task) in scopeJobs where !keys.contains(key) {
            task.cancel()
            scopeJobs[key] = nil
        }
        for (id, task) in marksJobs where !preparations.contains(id) {
            task.cancel()
            marksJobs[id] = nil
        }
    }

    func noteDisplayed(_ id: RenderedDiff.ID, published: Set<RenderedDiff.ID>) {
        displayed = displayed.intersection(published)
        displayed.insert(id)
    }

    var displayedFiles: Set<RenderedDiff.ID> { displayed }

    /// Whether `key`'s colour job is running, or ran to its end: either way it needs no new job.
    func isColored(_ key: ContentKey) -> Bool {
        colorJobs[key] != nil || endedColors.contains(key)
    }

    /// Whether the marks of `preparation` are being found, or were: either way they need no new job.
    func isMarked(_ preparation: UUID) -> Bool {
        marksJobs[preparation] != nil || endedMarks.contains(preparation)
    }

    /// Whether `key`'s scopes are being found, or were: either way they need no new job.
    func isScoped(_ key: ContentKey) -> Bool {
        scopeJobs[key] != nil || endedScopes.contains(key)
    }

    func trackScopes(_ task: Task<Void, Never>, for key: ContentKey) {
        scopeJobs[key] = task
    }

    /// Keeps a side's scopes; ``publish(_:)``, which every caller runs right after, trims what none shows any more.
    func land(_ lines: ScopeLines, for key: ContentKey) {
        if scopes[key] == nil { scopeOrder.append(key) }
        scopes[key] = (lines, nextVersion())
    }

    private func trimScopes() {
        let evicted = Self.oldest(in: &scopeOrder) { published.keys.contains($0) || scopeJobs[$0] != nil }
        for key in evicted {
            scopes[key] = nil
            endedScopes.remove(key)
        }
    }

    /// A side's scopes job ended; as ``endColors(_:cancelled:)``. A side whose scopes were not found has no ribbon.
    func endScopes(_ key: ContentKey, cancelled: Bool) {
        scopeJobs[key] = nil
        if !cancelled { endedScopes.insert(key) }
    }

    func trackColors(_ task: Task<Void, Never>, for key: ContentKey) {
        started += 1
        colorJobs[key] = task
    }

    func trackMarks(_ task: Task<Void, Never>, for preparation: UUID) {
        marksStarted += 1
        marksJobs[preparation] = task
    }

    /// Merges a tier's update into its side's layers; ``publish(_:)``, which every caller runs right after, trims
    /// what none shows any more.
    func land(_ update: TierUpdate, lineCount: Int, for key: ContentKey) {
        var entry = colors[key] ?? (LayeredLineTokens(lineCount: lineCount), 0)
        if colors[key] == nil { colorOrder.append(key) }
        entry.tokens.apply(update)
        entry.version = nextVersion()
        colors[key] = entry
    }

    private func trimColors() {
        let evicted = Self.oldest(in: &colorOrder) { published.keys.contains($0) || colorJobs[$0] != nil }
        for key in evicted {
            colors[key] = nil
            endedColors.remove(key)
        }
    }

    /// Adds what a marks job found for `preparation`; ``publish(_:)``, which every caller runs right after, trims
    /// what none shows any more.
    func land(_ found: MarksFound, for preparation: UUID) {
        var entry = marks[preparation] ?? Marks()
        if marks[preparation] == nil { marksOrder.append(preparation) }
        entry.old.merge(found.old) { $1 }
        entry.new.merge(found.new) { $1 }
        if let moved = found.moved { entry.moved = moved }
        entry.version = nextVersion()
        marks[preparation] = entry
    }

    private func trimMarks() {
        let evicted = Self.oldest(in: &marksOrder) { published.preparations.contains($0) || marksJobs[$0] != nil }
        for preparation in evicted {
            marks[preparation] = nil
            endedMarks.remove(preparation)
        }
    }

    /// Takes out of `order` its oldest entries past ``cacheCapacity``, but those `isKept` holds, which a published
    /// file shows or a job still lands in, and returns them.
    /// - Complexity: O(entries)
    private static func oldest<Key: Hashable>(in order: inout [Key], sparing isKept: (Key) -> Bool) -> [Key] {
        guard order.count > cacheCapacity else { return [] }
        var excess = order.count - cacheCapacity
        var evicted: [Key] = []
        order.removeAll { key in
            guard excess > 0, !isKept(key) else { return false }
            excess -= 1
            evicted.append(key)
            return true
        }
        return evicted
    }

    /// A side's colour job ended: when it ran to its end, the side is not coloured again, whatever its tiers found; when
    /// it was cancelled, the next display starts it again. Lines no tier reached stay plain.
    func endColors(_ key: ContentKey, cancelled: Bool) {
        colorJobs[key] = nil
        if !cancelled { endedColors.insert(key) }
    }

    /// A file's marks job ended; as ``endColors(_:cancelled:)``. Changes it did not reach, past its deadline, stay plain.
    func endMarks(_ preparation: UUID, cancelled: Bool) {
        marksJobs[preparation] = nil
        if !cancelled { endedMarks.insert(preparation) }
    }

    /// Sets ``byText`` to the decorations of `files`, each a published file with its parts; an unchanged file keeps its
    /// value, so its panes see nothing new.
    func publish(_ files: [(rendered: RenderedDiff, composition: Composition)]) {
        let compositions = files.map(\.composition)
        published = (
            Set(compositions.flatMap { [$0.old, $0.new] }.compactMap(\.self)), Set(compositions.map(\.preparation))
        )
        // What the files published before showed, and these do not, may go now.
        trimColors()
        trimScopes()
        trimMarks()
        var next: [UUID: DiffDecorations] = [:]
        var kept: [Composition: (inputs: Inputs, decorations: DiffDecorations)] = [:]
        for file in files {
            let parts = file.composition
            let old = parts.old.flatMap { colors[$0] }
            let new = parts.new.flatMap { colors[$0] }
            let found = marks[parts.preparation]
            let oldScopes = parts.old.flatMap { scopes[$0] }
            let newScopes = parts.new.flatMap { scopes[$0] }
            guard old != nil || new != nil || found != nil || oldScopes != nil || newScopes != nil else { continue }
            let inputs = Inputs(
                old: old?.version, new: new?.version, marks: found?.version, oldScopes: oldScopes?.version,
                newScopes: newScopes?.version)
            let decorations: DiffDecorations
            if let known = composed[parts] ?? kept[parts], known.inputs == inputs {
                decorations = known.decorations
            } else {
                let known = composed[parts] ?? kept[parts]
                let sameColors = known.map { $0.inputs.old == inputs.old && $0.inputs.new == inputs.new } ?? false
                let sameMarks =
                    known.map {
                        $0.inputs.marks == inputs.marks && $0.inputs.oldScopes == inputs.oldScopes
                            && $0.inputs.newScopes == inputs.newScopes
                    } ?? false
                decorations = DiffDecorations(
                    old: DiffDecorations.Side(
                        colors: old?.tokens, emphasis: found?.old ?? [:], scopes: oldScopes?.lines),
                    new: DiffDecorations.Side(
                        colors: new?.tokens, emphasis: found?.new ?? [:], scopes: newScopes?.lines),
                    moved: found?.moved,
                    colorVersion: sameColors ? known?.decorations.colorVersion ?? 0 : nextVersion(),
                    markVersion: sameMarks ? known?.decorations.markVersion ?? 0 : nextVersion())
            }
            kept[parts] = (inputs, decorations)
            for text in [file.rendered.unified, file.rendered.old, file.rendered.new].compactMap(\.self) {
                next[text.id] = decorations
            }
        }
        composed = kept
        let versions = { (all: [UUID: DiffDecorations]) in all.mapValues { [$0.colorVersion, $0.markVersion] } }
        if versions(next) != versions(byText) { byText = next }
    }
}

/// What a marks job found for some of a file's changes: each side's emphasis by source line, and the moved lines once.
struct MarksFound: Sendable {
    var old: [Int: [Range<Int>]] = [:]
    var new: [Int: [Range<Int>]] = [:]
    var moved: MovedLines?
}

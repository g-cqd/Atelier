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

    /// How many sides' colours, and files' marks, are kept, the oldest going first.
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
    /// The rendered files a pane reported on screen, kept while they stay published, so a change of setting decorates
    /// what shows.
    @ObservationIgnored private var displayed: Set<RenderedDiff.ID> = []
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
    }

    /// - Parameters:
    ///   - tiers: The tiers each displayed side may run: those of a language that supports it, those after the lexer
    ///     only while ``refinesSwiftColor`` holds.
    ///   - clock: The clock the stages' deadlines are measured on.
    package init(
        tiers: [any AtelierHighlighting.HighlightTier] = DiffDecorations.tiers(),
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.tiers = tiers
        self.clock = clock
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

    func trackColors(_ task: Task<Void, Never>, for key: ContentKey) {
        started += 1
        colorJobs[key] = task
    }

    func trackMarks(_ task: Task<Void, Never>, for preparation: UUID) {
        marksStarted += 1
        marksJobs[preparation] = task
    }

    /// Merges a tier's update into its side's layers, the oldest side past ``cacheCapacity`` going.
    func land(_ update: TierUpdate, lineCount: Int, for key: ContentKey) {
        var entry = colors[key] ?? (LayeredLineTokens(lineCount: lineCount), 0)
        if colors[key] == nil { colorOrder.append(key) }
        entry.tokens.apply(update)
        entry.version = nextVersion()
        colors[key] = entry
        if colorOrder.count > Self.cacheCapacity {
            for evicted in colorOrder.prefix(colorOrder.count - Self.cacheCapacity) {
                colors[evicted] = nil
                endedColors.remove(evicted)
            }
            colorOrder.removeFirst(colorOrder.count - Self.cacheCapacity)
        }
    }

    /// Adds what a marks job found for `preparation`, the oldest file past ``cacheCapacity`` going.
    func land(_ found: MarksFound, for preparation: UUID) {
        var entry = marks[preparation] ?? Marks()
        if marks[preparation] == nil { marksOrder.append(preparation) }
        entry.old.merge(found.old) { $1 }
        entry.new.merge(found.new) { $1 }
        if let moved = found.moved { entry.moved = moved }
        entry.version = nextVersion()
        marks[preparation] = entry
        if marksOrder.count > Self.cacheCapacity {
            for evicted in marksOrder.prefix(marksOrder.count - Self.cacheCapacity) {
                marks[evicted] = nil
                endedMarks.remove(evicted)
            }
            marksOrder.removeFirst(marksOrder.count - Self.cacheCapacity)
        }
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
        var next: [UUID: DiffDecorations] = [:]
        var kept: [Composition: (inputs: Inputs, decorations: DiffDecorations)] = [:]
        for file in files {
            let parts = file.composition
            let old = parts.old.flatMap { colors[$0] }
            let new = parts.new.flatMap { colors[$0] }
            let found = marks[parts.preparation]
            guard old != nil || new != nil || found != nil else { continue }
            let inputs = Inputs(old: old?.version, new: new?.version, marks: found?.version)
            let decorations: DiffDecorations
            if let known = composed[parts] ?? kept[parts], known.inputs == inputs {
                decorations = known.decorations
            } else {
                let known = composed[parts] ?? kept[parts]
                let sameColors = known.map { $0.inputs.old == inputs.old && $0.inputs.new == inputs.new } ?? false
                let sameMarks = known?.inputs.marks == inputs.marks && known != nil
                decorations = DiffDecorations(
                    old: DiffDecorations.Side(colors: old?.tokens, emphasis: found?.old ?? [:]),
                    new: DiffDecorations.Side(colors: new?.tokens, emphasis: found?.new ?? [:]), moved: found?.moved,
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

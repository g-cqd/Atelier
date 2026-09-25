import AemiCore
package import AtelierHighlighting
package import DiffCore
import DiffGit
package import DiffRendering
package import Foundation
import Observation

/// What the tiers after the lexer found for the files the pipeline publishes (PERF-11): swift-syntax's colour for each
/// displayed Swift side, over the lexer's first paint, through the core tier job (`HighlightTiers`).
///
/// A side is refined once per content: its blob id, which is a content hash on every kind of source, or, for a side
/// without one, the preparation that read it. Both sides of a file with one blob share one result, and a file shown
/// again, relaid out or reloaded unchanged, takes its colour from here at once, without a parse. A side's lines land
/// in chunks, the visible ones first, each merged into its ``LayeredLineTokens`` as it lands.
@MainActor
@Observable
package final class SwiftColorRefinement {
    /// What one side's refined tokens are kept under.
    package enum ContentKey: Hashable, Sendable {
        case blob(String, Language)
        /// A side without a blob id, which only its own preparation can vouch for.
        case preparation(UUID, RenderedSide)
    }

    /// What a refinement was started for: the pipeline's generation, the text it was asked for, and the content.
    struct Stamp {
        let generation: Int
        let textID: RenderedDiff.ID
        let key: ContentKey
    }

    /// How many sides' tokens are kept, the oldest going first.
    package static let cacheCapacity = 64

    /// The refined sides of every published text that has any, by ``RenderedText/id``: what a pane colours with.
    package private(set) var byText: [UUID: RefinedSides] = [:]
    /// Whether displayed Swift sides are refined; off, nothing is parsed and every pane keeps the lexer's colour.
    @ObservationIgnored package internal(set) var isEnabled = true
    /// How many tier jobs started, one per side; for tests and traces.
    @ObservationIgnored package private(set) var started = 0
    /// The tiers each displayed side runs, and the clock their deadlines are measured on.
    @ObservationIgnored let tiers: [any AtelierHighlighting.HighlightTier]
    @ObservationIgnored let clock: any Clock<Duration>
    @ObservationIgnored private var cache: [ContentKey: LayeredLineTokens] = [:]
    @ObservationIgnored private var cacheOrder: [ContentKey] = []
    @ObservationIgnored private var inFlight: [ContentKey: Task<Void, Never>] = [:]
    /// The sides whose job ran to its end, every tier finished or failed: they are not refined again.
    @ObservationIgnored private var ended: Set<ContentKey> = []
    /// The rendered files a pane reported on screen, kept while they stay published, so turning the setting on
    /// refines what shows.
    @ObservationIgnored private var displayed: Set<RenderedDiff.ID> = []
    /// Each file's refined sides by its two sides' keys, kept so a file's value, and so its panes, change only when
    /// one of its sides lands.
    @ObservationIgnored private var sidesByPair: [PairKey: RefinedSides] = [:]

    private struct PairKey: Hashable {
        let old: ContentKey?
        let new: ContentKey?
    }

    /// - Parameters:
    ///   - tiers: The tiers each displayed side runs.
    ///   - clock: The clock their deadlines are measured on.
    package init(
        tiers: [any AtelierHighlighting.HighlightTier] = RefinedSides.tiers(),
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.tiers = tiers
        self.clock = clock
    }

    /// Stops every refinement and forgets every result; which files show is kept.
    func reset() {
        for task in inFlight.values { task.cancel() }
        inFlight = [:]
        cache = [:]
        cacheOrder = []
        ended = []
        sidesByPair = [:]
        if !byText.isEmpty { byText = [:] }
    }

    /// Stops the refinements whose content no published file shows any more.
    func cancel(keeping keys: Set<ContentKey>) {
        for (key, task) in inFlight where !keys.contains(key) {
            task.cancel()
            inFlight[key] = nil
        }
    }

    func noteDisplayed(_ id: RenderedDiff.ID, published: Set<RenderedDiff.ID>) {
        displayed = displayed.intersection(published)
        displayed.insert(id)
    }

    var displayedFiles: Set<RenderedDiff.ID> { displayed }

    /// Whether `key`'s job is running, or ran to its end: either way it needs no new job.
    func isRefined(_ key: ContentKey) -> Bool {
        inFlight[key] != nil || ended.contains(key)
    }

    func track(_ task: Task<Void, Never>, for key: ContentKey) {
        started += 1
        inFlight[key] = task
    }

    /// Merges a tier's update into its side's layers, the oldest side past ``cacheCapacity`` going.
    func land(_ update: TierUpdate, lineCount: Int, for key: ContentKey) {
        if cache[key] == nil {
            cache[key] = LayeredLineTokens(lineCount: lineCount)
            cacheOrder.append(key)
        }
        cache[key]?.apply(update)
        if cacheOrder.count > Self.cacheCapacity {
            for evicted in cacheOrder.prefix(cacheOrder.count - Self.cacheCapacity) {
                cache[evicted] = nil
                ended.remove(evicted)
            }
            cacheOrder.removeFirst(cacheOrder.count - Self.cacheCapacity)
        }
        sidesByPair = sidesByPair.filter { $0.key.old != key && $0.key.new != key }
    }

    /// A side's job ended: when it ran to its end, the side is not refined again, whatever its tiers found; when it
    /// was cancelled, the next display starts it again. Lines no tier reached keep the lexer's colour.
    func end(_ key: ContentKey, cancelled: Bool) {
        inFlight[key] = nil
        if !cancelled { ended.insert(key) }
    }

    /// Sets ``byText`` to the refined sides of `files`, each a published file with its two sides' keys; unchanged
    /// entries keep their value, so their panes see nothing new.
    func publish(_ files: [(rendered: RenderedDiff, old: ContentKey?, new: ContentKey?)]) {
        var next: [UUID: RefinedSides] = [:]
        for file in files {
            let pair = PairKey(old: file.old, new: file.new)
            let sides: RefinedSides
            if let kept = sidesByPair[pair] {
                sides = kept
            } else {
                let old = file.old.flatMap { cache[$0] }
                let new = file.new.flatMap { cache[$0] }
                guard old != nil || new != nil else { continue }
                sides = RefinedSides(old: old, new: new)
                sidesByPair[pair] = sides
            }
            for text in [file.rendered.unified, file.rendered.old, file.rendered.new].compactMap(\.self) {
                next[text.id] = sides
            }
        }
        if next.mapValues(\.id) != byText.mapValues(\.id) { byText = next }
    }
}

extension RenderPipeline {
    /// Whether displayed Swift sides get swift-syntax's colour. Turning it off stops every refinement and gives every
    /// pane back the lexer's colour; turning it on refines the files on screen.
    package var refinesSwiftColor: Bool {
        get { refinement.isEnabled }
        set {
            guard newValue != refinement.isEnabled else { return }
            refinement.isEnabled = newValue
            refinement.reset()
            guard newValue else { return }
            for id in refinement.displayedFiles { refineDisplayed(id) }
        }
    }

    /// The refined sides of the published text `id`, for the pane that shows it; nil while none has landed.
    package func refinedSides(forText id: UUID) -> RefinedSides? {
        refinement.byText[id]
    }

    /// Starts the syntactic tier on each Swift side of the published file `id`, which a pane now shows, unless its
    /// content is refined or being refined already; a side refined already reaches the file's panes at once.
    package func refineDisplayed(_ id: RenderedDiff.ID) {
        let files = publishedFiles()
        refinement.noteDisplayed(id, published: Set(files.map(\.rendered.id)))
        guard refinement.isEnabled else { return }
        refinement.cancel(keeping: Set(files.flatMap { [$0.old, $0.new] }.compactMap(\.self)))
        if let file = files.first(where: { $0.rendered.id == id }) {
            for side in [RenderedSide.old, .new] { start(side, of: file, textID: id) }
        }
        refinement.publish(files.map { ($0.rendered, $0.old, $0.new) })
    }

    /// A published file: what shows, what it was prepared from, and its sides' keys, nil for a side that is absent or
    /// not Swift.
    private struct PublishedFile {
        let rendered: RenderedDiff
        let diff: PreparedDiff
        let old: SwiftColorRefinement.ContentKey?
        let new: SwiftColorRefinement.ContentKey?
    }

    private func publishedFiles() -> [PublishedFile] {
        guard let target else { return [] }
        let rendered: [RenderedDiff] =
            switch target {
                case .file: file.map { [$0] } ?? []
                case .cards: cards.map(\.rendered)
            }
        return zip(rendered, zip(prepared, target.pairs))
            .map { rendered, prepared in
                let (diff, pair) = prepared
                return PublishedFile(
                    rendered: rendered, diff: diff, old: Self.key(of: pair.old, side: .old, in: diff),
                    new: Self.key(of: pair.new, side: .new, in: diff))
            }
    }

    /// The key a side is refined under; nil when the side is absent or empty, or its file is not Swift.
    private static func key(of entry: SourceEntry?, side: RenderedSide, in diff: PreparedDiff)
        -> SwiftColorRefinement.ContentKey?
    {
        guard diff.language == .swift, let entry else { return nil }
        guard !(side == .old ? diff.oldText : diff.newText).isEmpty else { return nil }
        if let blob = entry.blobID { return .blob(blob, diff.language) }
        return .preparation(diff.id, side)
    }

    /// Runs the tier job on one side of `file`, unless its content is refined already or being refined: each update
    /// lands on the main actor as it comes, the visible lines first.
    private func start(_ side: RenderedSide, of file: PublishedFile, textID: RenderedDiff.ID) {
        guard let key = side == .old ? file.old : file.new, !refinement.isRefined(key) else { return }
        let text = side == .old ? file.diff.oldText : file.diff.newText
        let lines = side == .old ? file.diff.model.oldLines : file.diff.model.newLines
        let request = TierRequest(
            revision: Self.revision(of: key, path: file.diff.title, language: file.diff.language), text: text,
            lineRanges: DiffRenderer.lineRanges(of: text, lines: lines),
            visibleLines: Self.visibleLines(of: side, in: file.diff), unit: .utf16)
        let stamp = SwiftColorRefinement.Stamp(generation: generation, textID: textID, key: key)
        let lineCount = lines.count
        let tiers = refinement.tiers
        let clock = refinement.clock
        refinement.track(
            taskProvider.task(priority: .utility) {
                await HighlightTiers.run(request, tiers: tiers, clock: clock) { event in
                    guard case .update(let update) = event else { return }
                    await self.land(update, lineCount: lineCount, stamp: stamp)
                }
                self.refinement.end(key, cancelled: Task.isCancelled)
            }, for: key)
    }

    /// Takes a tier's update, unless its job was cancelled, or its render was superseded and no published file shows
    /// its content any more; then colours every published text that shows it.
    private func land(_ update: TierUpdate, lineCount: Int, stamp: SwiftColorRefinement.Stamp) {
        let files = publishedFiles()
        let isShown = files.contains { $0.rendered.id == stamp.textID || $0.old == stamp.key || $0.new == stamp.key }
        guard !Task.isCancelled, refinement.isEnabled, stamp.generation == generation || isShown else { return }
        refinement.land(update, lineCount: lineCount, for: stamp.key)
        refinement.publish(files.map { ($0.rendered, $0.old, $0.new) })
    }

    /// The revision a side's job reads: its file's path, its language and its content's key.
    private static func revision(of key: SwiftColorRefinement.ContentKey, path: String, language: Language)
        -> SourceRevision
    {
        switch key {
            case .blob(let blob, _): SourceRevision(documentID: path, language: language, key: .content(blob))
            case .preparation(let id, let side):
                SourceRevision(documentID: path, language: language, key: .content("\(id.uuidString)/\(side)"))
        }
    }

    /// The lines of `side` a pane most likely shows first: those around the file's first change, where a file opens
    /// by default, or its top when it has none. The job colours them first; the pipeline does not know the viewport.
    private static func visibleLines(of side: RenderedSide, in diff: PreparedDiff) -> Range<Int> {
        let rows = diff.model.splitRows
        let first =
            diff.model.splitChangeRanges.lazy.flatMap { rows[$0] }
            .compactMap { side == .old ? $0.old?.index : $0.new?.index }.first ?? 0
        let start = max(first - Self.linesAboveChange, 0)
        return start ..< start + Self.visibleLineCount
    }

    /// How many lines the job colours first, and how many of them lie above the first change.
    private static let visibleLineCount = 80
    private static let linesAboveChange = 20
}

import AemiCore
package import DiffCore
import DiffGit
package import DiffRendering
package import Foundation
import Observation

/// What the syntactic tier found for the files the pipeline publishes (PERF-11 step 1): swift-syntax's colour for each
/// displayed Swift side, over the lexer's first paint.
///
/// A side is refined once per content: its blob id, which is a content hash on every kind of source, or, for a side
/// without one, the preparation that read it. Both sides of a file with one blob share one result, and a file shown
/// again, relaid out or reloaded unchanged, takes its colour from here at once, without a parse.
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
    /// How many refinements started, a parse each; for tests and traces.
    @ObservationIgnored package private(set) var started = 0
    @ObservationIgnored let refiner: SyntaxRefiner
    @ObservationIgnored private var cache: [ContentKey: LineTokens] = [:]
    @ObservationIgnored private var cacheOrder: [ContentKey] = []
    @ObservationIgnored private var inFlight: [ContentKey: Task<Void, Never>] = [:]
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

    init(refiner: SyntaxRefiner) {
        self.refiner = refiner
    }

    /// Stops every refinement and forgets every result; which files show is kept.
    func reset() {
        for task in inFlight.values { task.cancel() }
        inFlight = [:]
        cache = [:]
        cacheOrder = []
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

    func tokens(for key: ContentKey) -> LineTokens? {
        cache[key]
    }

    func isRunning(_ key: ContentKey) -> Bool {
        inFlight[key] != nil
    }

    func track(_ task: Task<Void, Never>, for key: ContentKey) {
        started += 1
        inFlight[key] = task
    }

    /// Takes a refinement's tokens under its key, the oldest past ``cacheCapacity`` going.
    func land(_ tokens: LineTokens, for key: ContentKey) {
        inFlight[key] = nil
        if cache.updateValue(tokens, forKey: key) == nil { cacheOrder.append(key) }
        if cacheOrder.count > Self.cacheCapacity {
            for evicted in cacheOrder.prefix(cacheOrder.count - Self.cacheCapacity) { cache[evicted] = nil }
            cacheOrder.removeFirst(cacheOrder.count - Self.cacheCapacity)
        }
        sidesByPair = sidesByPair.filter { $0.key.old != key && $0.key.new != key }
    }

    /// A refinement that ended without tokens: the side keeps the lexer's colour.
    func fail(_ key: ContentKey) {
        inFlight[key] = nil
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

    private func start(_ side: RenderedSide, of file: PublishedFile, textID: RenderedDiff.ID) {
        guard let key = side == .old ? file.old : file.new, refinement.tokens(for: key) == nil,
            !refinement.isRunning(key)
        else { return }
        let text = side == .old ? file.diff.oldText : file.diff.newText
        let lines = side == .old ? file.diff.model.oldLines : file.diff.model.newLines
        let stamp = SwiftColorRefinement.Stamp(generation: generation, textID: textID, key: key)
        let refiner = refinement.refiner
        refinement.track(
            taskProvider.task(priority: .utility) {
                do {
                    let tokens = try await refiner.refine(text, lines: lines)
                    self.land(tokens, stamp: stamp)
                } catch {
                    self.refinement.fail(key)
                }
            }, for: key)
    }

    /// Takes a refinement that landed, unless it was cancelled, or its render was superseded and no published file
    /// shows its content any more; then colours every published text that shows it.
    private func land(_ tokens: LineTokens, stamp: SwiftColorRefinement.Stamp) {
        let files = publishedFiles()
        let isShown = files.contains { $0.rendered.id == stamp.textID || $0.old == stamp.key || $0.new == stamp.key }
        guard !Task.isCancelled, refinement.isEnabled, stamp.generation == generation || isShown else {
            refinement.fail(stamp.key)
            return
        }
        refinement.land(tokens, for: stamp.key)
        refinement.publish(files.map { ($0.rendered, $0.old, $0.new) })
    }
}

package import AemiCore
package import DiffCore
package import DiffGit
package import DiffRendering
import Foundation
import Observation

/// Turns the selection into what the detail area shows: one document for a file, one card per file for a folder.
/// Every publish carries the generation it belongs to, so a superseded render can never overwrite a newer one, and
/// re-layouts never cancel a load that is still streaming cards in.
@MainActor
@Observable
package final class RenderPipeline {
    package enum Target: Equatable {
        case file(FilePair)
        case cards([FilePair])

        package var pairs: [FilePair] {
            switch self {
                case .file(let pair): [pair]
                case .cards(let pairs): pairs
            }
        }

        package var isCards: Bool {
            if case .cards = self { true } else { false }
        }
    }

    package enum Event {
        /// A render reached the model; `isFirst` for the file or the first card of a generation.
        case published(RenderedDiff.ID, isFirst: Bool)
        case finished
        case failed(String)
    }

    /// The sources and diff options of one render, bundled to keep the helpers under the parameter-count limit.
    private struct RenderInputs {
        let left: ComparisonSource
        let right: ComparisonSource
        let granularity: IntralineGranularity
        let heuristics: DiffHeuristics
    }

    package private(set) var file: RenderedDiff?
    package private(set) var cards: [RenderedFile] = []
    package private(set) var target: Target?
    /// Rows revealed around gaps of the current document, keyed per file and gap.
    package private(set) var gapExpansions: [GapKey: GapExpansion] = [:]
    package private(set) var error: String?
    /// Diffs of the current target, kept so layout changes and gap drags re-render without reloading or re-diffing.
    @ObservationIgnored package private(set) var prepared: [PreparedDiff] = []
    @ObservationIgnored package var onEvent: ((Event) -> Void)?

    /// Bumped by every fresh render; work from an older generation is dropped when it lands.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var completedGeneration = 0
    /// Whether a render is in flight: `completedGeneration < generation`, mirrored into an observed store so an
    /// observer sees both edges, since `generation` is bumped inside update passes and cannot be observed itself.
    package private(set) var isRendering = false
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var options: DiffRenderer.Options
    @ObservationIgnored private var layout: (context: Int, isolates: Bool) = (3, false)

    /// Granularity and heuristics of what is published; a render reuses published work only when they match.
    @ObservationIgnored private var publishedGranularity: IntralineGranularity?
    @ObservationIgnored private var publishedHeuristics: DiffHeuristics?

    private let preparer: DiffPreparer
    private let taskProvider: any TaskProvider
    private let renderer: PaneRenderer

    package init(
        preparer: DiffPreparer, taskProvider: any TaskProvider, options: DiffRenderer.Options,
        renderer: PaneRenderer = .live
    ) {
        self.preparer = preparer
        self.taskProvider = taskProvider
        self.options = options
        self.renderer = renderer
    }

    /// Options for the next renders; re-renders of prepared diffs happen through `relayout`.
    package func configure(options: DiffRenderer.Options, context: Int, isolatesChanges: Bool) {
        self.options = options
        layout = (context, isolatesChanges)
    }

    package func clear() {
        task?.cancel()
        generation += 1
        completedGeneration = generation
        isRendering = false
        file = nil
        cards = []
        prepared = []
        target = nil
        error = nil
    }

    /// Renders `target`. Whatever is already prepared is published in this very update, before any task hop. A pair
    /// with the same path, blobs and diff options as a published one reuses its prepared and rendered diff, so the
    /// views keyed on them never rebuild.
    package func render(
        _ target: Target, left: ComparisonSource, right: ComparisonSource, granularity: IntralineGranularity,
        heuristics: DiffHeuristics
    ) {
        let inputs = RenderInputs(left: left, right: right, granularity: granularity, heuristics: heuristics)
        task?.cancel()
        let reuse = reuse(for: target, granularity: granularity, heuristics: heuristics)
        generation += 1
        isRendering = true
        let generation = generation
        self.target = target
        publishedGranularity = granularity
        publishedHeuristics = heuristics
        file = nil
        cards = []
        prepared = []
        error = nil
        gapExpansions = reusableGapExpansions(gapExpansions, target: target, reuse: reuse)
        preparer.cancelPrefetch()

        switch target {
            case .file(let pair):
                if let reused = reuse.file {
                    prepared = reuse.preparedByIdentity[PairIdentity(pair)].map { [$0] } ?? []
                    file = reused
                    finish(generation)
                    return
                }
                renderFresh(target, inputs: inputs, keepingScroll: reuse.sameFilePath, generation: generation)
            case .cards(let pairs):
                guard !reuse.cardsByIdentity.isEmpty else {
                    renderFresh(target, inputs: inputs, keepingScroll: false, generation: generation)
                    return
                }
                renderCardsDifferentially(pairs, reuse: reuse, inputs: inputs, generation: generation)
        }
    }

    /// Re-lays out what is prepared with the current options; a load still streaming in keeps going and renders
    /// its remaining cards with the same options when they land.
    package func relayout(keepingScroll: Bool) {
        guard let target, !prepared.isEmpty else { return }
        if !keepingScroll { gapExpansions = [:] }
        let rendered = Self.render(
            prepared, target: target, options: options, layout: renderLayout, keepingScroll: keepingScroll)
        switch target {
            case .file:
                file = rendered.file
            case .cards:
                cards = rendered.cards
        }
        if !isRendering { onEvent?(.finished) }
    }

    /// Reveals rows around a gap on top of `base`: dragging down pulls rows from the hunk above, dragging up from the
    /// hunk below; a gap at the top or bottom of a file reveals in its only possible direction whichever way it is
    /// dragged. The document is re-laid out in place.
    package func adjustGap(_ marker: GapMarker, from base: GapExpansion, byLines delta: Int) {
        let effective = marker.isLeading ? -abs(delta) : marker.isTrailing ? abs(delta) : delta
        let expansion = GapExpansion(below: base.below + max(effective, 0), above: base.above + max(-effective, 0))
        guard gapExpansions[marker.key] != expansion else { return }
        gapExpansions[marker.key] = expansion
        relayout(keepingScroll: true)
    }

    /// Folds every revealed gap back to the context lines, keeping the scroll position.
    package func resetGaps() {
        guard !gapExpansions.isEmpty else { return }
        gapExpansions = [:]
        relayout(keepingScroll: true)
    }

    package func expansion(of key: GapKey) -> GapExpansion {
        gapExpansions[key] ?? GapExpansion()
    }

    private var renderLayout: RenderLayout {
        layout.isolates || target?.isCards == true
            ? .changes(context: layout.context, expansions: gapExpansions) : .full
    }

    private func publish(_ rendered: Rendered, generation: Int, appending: Bool) {
        guard generation == self.generation else { return }
        switch rendered {
            case .file(let diff):
                PhaseTrace.log("publish file")
                file = diff
                onEvent?(.published(diff.id, isFirst: true))
            case .cards(let files):
                guard !files.isEmpty else { return }
                PhaseTrace.log("publish \(files.count) cards\(appending ? " more" : "")")
                if appending {
                    cards += files
                    onEvent?(.published(files[0].rendered.id, isFirst: false))
                } else {
                    cards = files
                    onEvent?(.published(files[0].rendered.id, isFirst: true))
                }
        }
    }

    private func finish(_ generation: Int) {
        guard generation == self.generation else { return }
        PhaseTrace.log("finish")
        completedGeneration = generation
        isRendering = false
        onEvent?(.finished)
    }

    private enum Rendered {
        case file(RenderedDiff)
        case cards([RenderedFile])

        var file: RenderedDiff? { if case .file(let diff) = self { diff } else { nil } }
        var cards: [RenderedFile] { if case .cards(let files) = self { files } else { [] } }
    }

    /// Pure, so it runs inline for a cache hit and off the main actor for a batch.
    nonisolated private static func render(
        _ prepared: [PreparedDiff], target: Target, options: DiffRenderer.Options, layout: RenderLayout,
        keepingScroll: Bool, firstIndex: Int = 0
    ) -> Rendered {
        switch target {
            case .file:
                var rendered = DiffRenderer.render(
                    prepared: prepared, options: options, layout: layout, withHeaders: false)
                rendered.keepsScrollPosition = keepingScroll
                return .file(rendered)
            case .cards:
                return .cards(
                    prepared.enumerated()
                        .map { offset, file in
                            var rendered = DiffRenderer.render(
                                prepared: [file], options: options, layout: layout, withHeaders: false,
                                firstFileIndex: firstIndex + offset)
                            rendered.keepsScrollPosition = keepingScroll
                            return RenderedFile(path: file.title, rendered: rendered)
                        })
        }
    }

    /// Renders `prepared` off the main actor through ``renderer``, the way `render` does inline.
    private func renderOffMain(
        _ prepared: [PreparedDiff], target: Target, options: DiffRenderer.Options, layout: RenderLayout,
        keepingScroll: Bool, firstIndex: Int = 0
    ) async throws -> Rendered {
        let jobs = prepared.enumerated().map { PaneRenderer.Job(index: firstIndex + $0.offset, diff: $0.element) }
        let panes = try await renderer.render(jobs, options: options, layout: layout)
        switch target {
            case .file:
                guard var pane = panes.first else { throw IncompleteRender() }
                pane.keepsScrollPosition = keepingScroll
                return .file(pane)
            case .cards:
                return .cards(
                    zip(prepared, panes)
                        .map { diff, pane in
                            var pane = pane
                            pane.keepsScrollPosition = keepingScroll
                            return RenderedFile(path: diff.title, rendered: pane)
                        })
        }
    }

    /// A renderer that answered fewer panes than it was given diffs.
    private struct IncompleteRender: LocalizedError {
        var errorDescription: String? { "The diff could not be rendered." }
    }
}

/// Reuse of the published state across renders, so a reload leaves unchanged files untouched.
extension RenderPipeline {
    /// A pair's rendering identity: its path and both blob ids. Pairs with the same identity produce the same diff.
    private struct PairIdentity: Hashable {
        let path: String
        let oldBlob: String?
        let newBlob: String?
        private let oldPresent: Bool
        private let newPresent: Bool

        init(_ pair: FilePair) {
            path = pair.path
            oldBlob = pair.old?.blobID
            newBlob = pair.new?.blobID
            oldPresent = pair.old != nil
            newPresent = pair.new != nil
        }

        /// False when a present side has no blob id: `SourceLoader` skips hashing large working-tree files, so such
        /// a pair can never prove its content unchanged.
        var isReusable: Bool {
            (!oldPresent || oldBlob != nil) && (!newPresent || newBlob != nil)
        }
    }

    /// What the published state lends the next render: prepared diffs and cards by identity, or the rendered file.
    private struct Reuse {
        var file: RenderedDiff?
        /// Whether the previous `.file` target had the same path, whatever its blobs, so a reload keeps the scroll.
        var sameFilePath = false
        var preparedByIdentity: [PairIdentity: PreparedDiff] = [:]
        var cardsByIdentity: [PairIdentity: RenderedFile] = [:]
    }

    /// What the next render can reuse from the published state; nothing when the granularity or heuristics differ.
    /// A render still streaming lends the prefix that landed. Call before clearing the published state.
    private func reuse(for target: Target, granularity: IntralineGranularity, heuristics: DiffHeuristics) -> Reuse {
        var reuse = Reuse()
        guard granularity == publishedGranularity, heuristics == publishedHeuristics, let previousTarget = self.target
        else { return reuse }
        let oldPairs = previousTarget.pairs
        switch previousTarget {
            case .file(let pair):
                guard let oldPrepared = prepared.first else { return reuse }
                let identity = PairIdentity(pair)
                if case .file(let newPair) = target { reuse.sameFilePath = newPair.path == pair.path }
                guard identity.isReusable else { return reuse }
                reuse.preparedByIdentity[identity] = oldPrepared
                if case .file(let newPair) = target, PairIdentity(newPair) == identity { reuse.file = file }
            case .cards:
                // A card's rows bake in its `firstFileIndex`, which hover maps hits back by, so only a pair that
                // kept its position is reused.
                guard case .cards(let newPairs) = target else { return reuse }
                let landed = min(oldPairs.count, prepared.count, cards.count)
                for index in 0 ..< landed where index < newPairs.count {
                    let identity = PairIdentity(oldPairs[index])
                    guard identity.isReusable, identity == PairIdentity(newPairs[index]) else { continue }
                    reuse.preparedByIdentity[identity] = prepared[index]
                    reuse.cardsByIdentity[identity] = cards[index]
                }
        }
        return reuse
    }

    /// The gap expansions to carry into this render: only those of files reused as is, whose rows already have them
    /// baked in. A freshly rendered file starts with every gap collapsed.
    private func reusableGapExpansions(_ current: [GapKey: GapExpansion], target: Target, reuse: Reuse)
        -> [GapKey: GapExpansion]
    {
        switch target {
            case .file:
                return reuse.file != nil ? current : [:]
            case .cards(let pairs):
                let reusedIndices = Set(pairs.indices.filter { reuse.cardsByIdentity[PairIdentity(pairs[$0])] != nil })
                guard !reusedIndices.isEmpty else { return [:] }
                return current.filter { reusedIndices.contains($0.key.fileIndex) }
        }
    }

    /// Prepares and renders every pair of `target`, publishing the first as soon as it lands and the rest in one
    /// batch behind it.
    private func renderFresh(_ target: Target, inputs: RenderInputs, keepingScroll: Bool, generation: Int) {
        let pairs = target.pairs
        if let head = pairs.first,
            let cached = preparer.cached(head, granularity: inputs.granularity, heuristics: inputs.heuristics)
        {
            prepared = [cached]
            publish(
                Self.render(
                    prepared, target: target, options: options, layout: renderLayout, keepingScroll: keepingScroll),
                generation: generation, appending: false)
            if pairs.count == 1 {
                finish(generation)
                return
            }
        }
        task = taskProvider.task {
            do {
                if prepared.isEmpty {
                    let head = try await preparer.prepare(
                        Array(pairs.prefix(1)), left: inputs.left, right: inputs.right,
                        granularity: inputs.granularity, heuristics: inputs.heuristics)
                    guard generation == self.generation else { return }
                    prepared = head
                    publish(
                        try await renderOffMain(
                            head, target: target, options: options, layout: renderLayout,
                            keepingScroll: keepingScroll),
                        generation: generation, appending: false)
                }
                if pairs.count > 1 {
                    let tail = try await preparer.prepare(
                        Array(pairs.dropFirst()), left: inputs.left, right: inputs.right,
                        granularity: inputs.granularity, heuristics: inputs.heuristics)
                    guard generation == self.generation else { return }
                    prepared += tail
                    publish(
                        try await renderOffMain(
                            tail, target: target, options: options, layout: renderLayout,
                            keepingScroll: keepingScroll, firstIndex: 1), generation: generation, appending: true)
                }
                finish(generation)
            } catch is CancellationError {
                return
            } catch {
                guard generation == self.generation else { return }
                self.error = error.localizedDescription
                completedGeneration = generation
                isRendering = false
                onEvent?(.failed(error.localizedDescription))
            }
        }
    }

    /// Renders a card list, preparing and rendering only the pairs `reuse` cannot lend. Publishes once, in the
    /// target's order.
    private func renderCardsDifferentially(
        _ pairs: [FilePair], reuse: Reuse, inputs: RenderInputs, generation: Int
    ) {
        let identities = pairs.map(PairIdentity.init)
        let missingIndices = identities.indices.filter { reuse.cardsByIdentity[identities[$0]] == nil }

        guard !missingIndices.isEmpty else {
            prepared = identities.compactMap { reuse.preparedByIdentity[$0] }
            publish(
                .cards(identities.compactMap { reuse.cardsByIdentity[$0] }), generation: generation, appending: false)
            finish(generation)
            return
        }

        let missingPairs = missingIndices.map { pairs[$0] }
        // Each missing card renders at its own index: missing pairs are not contiguous, so no block offset applies.
        let options = self.options
        let layout = renderLayout
        task = taskProvider.task {
            do {
                let freshPrepared = try await self.preparer.prepare(
                    missingPairs, left: inputs.left, right: inputs.right, granularity: inputs.granularity,
                    heuristics: inputs.heuristics)
                guard generation == self.generation else { return }
                let jobs = zip(missingIndices, freshPrepared).map { PaneRenderer.Job(index: $0, diff: $1) }
                let freshCards = zip(
                    freshPrepared, try await self.renderer.render(jobs, options: options, layout: layout)
                )
                .map { RenderedFile(path: $0.title, rendered: $1) }
                guard generation == self.generation else { return }
                let freshPreparedByIdentity = Dictionary(
                    zip(missingPairs.map(PairIdentity.init), freshPrepared), uniquingKeysWith: { first, _ in first })
                let freshCardsByIdentity = Dictionary(
                    zip(missingPairs.map(PairIdentity.init), freshCards), uniquingKeysWith: { first, _ in first })
                var mergedPrepared: [PreparedDiff] = []
                var mergedCards: [RenderedFile] = []
                mergedPrepared.reserveCapacity(identities.count)
                mergedCards.reserveCapacity(identities.count)
                for identity in identities {
                    if let kept = reuse.preparedByIdentity[identity], let card = reuse.cardsByIdentity[identity] {
                        mergedPrepared.append(kept)
                        mergedCards.append(card)
                    } else if let fresh = freshPreparedByIdentity[identity], let card = freshCardsByIdentity[identity] {
                        mergedPrepared.append(fresh)
                        mergedCards.append(card)
                    }
                }
                self.prepared = mergedPrepared
                self.publish(.cards(mergedCards), generation: generation, appending: false)
                self.finish(generation)
            } catch is CancellationError {
                return
            } catch {
                guard generation == self.generation else { return }
                self.error = error.localizedDescription
                self.completedGeneration = generation
                self.isRendering = false
                self.onEvent?(.failed(error.localizedDescription))
            }
        }
    }
}

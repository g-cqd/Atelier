import DiffConcurrency
import DiffCore
import DiffGit
import DiffRendering
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
    private var completedGeneration = 0
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var options: DiffRenderer.Options
    @ObservationIgnored private var layout: (context: Int, isolates: Bool) = (3, false)

    private let preparer: DiffPreparer
    private let taskProvider: any TaskProvider

    package init(preparer: DiffPreparer, taskProvider: any TaskProvider, options: DiffRenderer.Options) {
        self.preparer = preparer
        self.taskProvider = taskProvider
        self.options = options
    }

    package var isRendering: Bool { completedGeneration < generation }

    /// Options for the next renders; re-renders of prepared diffs happen through `relayout`.
    package func configure(options: DiffRenderer.Options, context: Int, isolatesChanges: Bool) {
        self.options = options
        layout = (context, isolatesChanges)
    }

    package func clear() {
        task?.cancel()
        generation += 1
        completedGeneration = generation
        file = nil
        cards = []
        prepared = []
        target = nil
        error = nil
    }

    /// Renders `target` afresh. Whatever is already prepared is published in this very update, before any task hop.
    package func render(_ target: Target, left: ComparisonSource, right: ComparisonSource, granularity: IntralineGranularity, heuristics: DiffHeuristics) {
        task?.cancel()
        generation += 1
        let generation = generation
        self.target = target
        file = nil
        cards = []
        prepared = []
        error = nil
        gapExpansions = [:]
        preparer.cancelPrefetch()

        let pairs = target.pairs
        if let head = pairs.first, let cached = preparer.cached(head, granularity: granularity, heuristics: heuristics) {
            prepared = [cached]
            publish(Self.render(prepared, target: target, options: options, layout: renderLayout, keepingScroll: false), generation: generation, appending: false)
            if pairs.count == 1 {
                finish(generation)
                return
            }
        }
        task = taskProvider.task {
            do {
                if prepared.isEmpty {
                    let head = try await preparer.prepare(Array(pairs.prefix(1)), left: left, right: right, granularity: granularity, heuristics: heuristics)
                    guard generation == self.generation else { return }
                    prepared = head
                    publish(try await Self.renderOffMain(head, target: target, options: options, layout: renderLayout, keepingScroll: false), generation: generation, appending: false)
                }
                if pairs.count > 1 {
                    let tail = try await preparer.prepare(Array(pairs.dropFirst()), left: left, right: right, granularity: granularity, heuristics: heuristics)
                    guard generation == self.generation else { return }
                    prepared += tail
                    publish(try await Self.renderOffMain(tail, target: target, options: options, layout: renderLayout, keepingScroll: false, firstIndex: 1), generation: generation, appending: true)
                }
                finish(generation)
            } catch is CancellationError {
                return
            } catch {
                guard generation == self.generation else { return }
                self.error = error.localizedDescription
                completedGeneration = generation
                onEvent?(.failed(error.localizedDescription))
            }
        }
    }

    /// Re-lays out what is prepared with the current options; a load still streaming in keeps going and renders
    /// its remaining cards with the same options when they land.
    package func relayout(keepingScroll: Bool) {
        guard let target, !prepared.isEmpty else { return }
        if !keepingScroll { gapExpansions = [:] }
        let rendered = Self.render(prepared, target: target, options: options, layout: renderLayout, keepingScroll: keepingScroll)
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
        layout.isolates || target?.isCards == true ? .changes(context: layout.context, expansions: gapExpansions) : .full
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
        _ prepared: [PreparedDiff], target: Target, options: DiffRenderer.Options, layout: RenderLayout, keepingScroll: Bool, firstIndex: Int = 0
    ) -> Rendered {
        switch target {
        case .file:
            var rendered = DiffRenderer.render(prepared: prepared, options: options, layout: layout, withHeaders: false)
            rendered.keepsScrollPosition = keepingScroll
            return .file(rendered)
        case .cards:
            return .cards(prepared.enumerated().map { offset, file in
                var rendered = DiffRenderer.render(prepared: [file], options: options, layout: layout, withHeaders: false, firstFileIndex: firstIndex + offset)
                rendered.keepsScrollPosition = keepingScroll
                return RenderedFile(path: file.title, rendered: rendered)
            })
        }
    }

    @concurrent
    private static func renderOffMain(
        _ prepared: [PreparedDiff], target: Target, options: DiffRenderer.Options, layout: RenderLayout, keepingScroll: Bool, firstIndex: Int = 0
    ) async throws -> Rendered {
        switch target {
        case .file:
            return render(prepared, target: target, options: options, layout: layout, keepingScroll: keepingScroll)
        case .cards:
            let indexed = Array(prepared.enumerated())
            let files = try await mapConcurrently(indexed, limit: ProcessInfo.processInfo.activeProcessorCount) { offset, file in
                render([file], target: target, options: options, layout: layout, keepingScroll: keepingScroll, firstIndex: firstIndex + offset).cards[0]
            }
            return .cards(files)
        }
    }
}

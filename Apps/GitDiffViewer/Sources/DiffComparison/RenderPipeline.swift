package import AemiCore
package import DiffCore
package import DiffGit
package import DiffRendering
import Foundation
import Observation

/// Turns the selection into what the detail area shows: one document for a file, one card per file for a folder.
///
/// A render either starts from nothing, publishing the first file as soon as it lands and the rest behind it, or keeps
/// what is published on screen until the whole replacement lands in one step. Every render carries its generation, so
/// a superseded one never overwrites a newer one. What is published stays interactive meanwhile, gap drags and
/// relayouts included: each published file keeps the stamp it was rendered under, and work that lands under a stamp
/// that moved on is rendered again rather than shown out of date.
@MainActor
@Observable
package final class RenderPipeline {
    package enum Event {
        /// A render reached the model; `isFirst` for the file or the first card of a generation.
        case published(RenderedDiff.ID, isFirst: Bool)
        case finished
        case failed(String)
    }

    /// The two sources a render compares.
    package struct Sources: Equatable, Sendable {
        package let left: ComparisonSource
        package let right: ComparisonSource
    }

    /// The sources and diff options of one render.
    private struct RenderInputs {
        let sources: Sources
        let granularity: IntralineGranularity
        let heuristics: DiffHeuristics
    }

    /// What a published file was rendered under: the rendering configuration, whether it shows changes only, and its
    /// own gap expansions by gap index. A file whose stamp is no longer the current one shows something stale.
    private struct Stamp: Equatable {
        let configuration: Int
        let showsChangesOnly: Bool
        let expansions: [Int: GapExpansion]
    }

    /// A rendered file with the stamp it was rendered under.
    private typealias Stamped = (file: RenderedDiff, stamp: Stamp)

    package private(set) var file: RenderedDiff?
    package private(set) var cards: [RenderedFile] = []
    /// The target of what is published; `prepared` holds its diffs, one per pair that landed, in order.
    package private(set) var target: Target?
    /// The sources `file` or `cards` were rendered from, set in the same step as they are; nil while neither shows
    /// anything. The model compares them with the sides' own to tell a previous comparison kept on screen.
    package private(set) var publishedSources: Sources?
    /// Rows revealed around the gaps of what is published, keyed per file and gap.
    package private(set) var gapExpansions: [GapKey: GapExpansion] = [:]
    package private(set) var error: String?
    /// Diffs of what is published, kept so layout changes and gap drags re-render without reloading or re-diffing.
    @ObservationIgnored package private(set) var prepared: [PreparedDiff] = []
    @ObservationIgnored package var onEvent: ((Event) -> Void)?
    /// The stamp each published file was rendered under, parallel to `prepared`.
    @ObservationIgnored private var stamps: [Stamp] = []

    /// Bumped by every render; work from an older generation is dropped when it lands.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var completedGeneration = 0
    /// Whether a render is in flight: `completedGeneration < generation`, mirrored into an observed store so an
    /// observer sees both edges, since `generation` is bumped inside update passes and cannot be observed itself.
    /// It stays true until the replacement of what is kept on screen has landed, so kept content never reads as final.
    package private(set) var isRendering = false
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var options: DiffRenderer.Options
    @ObservationIgnored private var layout: (context: Int, isolates: Bool) = (3, false)
    /// Bumped whenever `configure` changes how diffs render, which leaves every stamp before it stale.
    @ObservationIgnored private var configuration = 0
    /// Bumped whenever what is published is replaced or taken away, not when it is rendered again or extended; a
    /// relayout lands only on the content it rendered.
    @ObservationIgnored private var contentVersion = 0
    @ObservationIgnored private var relayoutTask: Task<Void, Never>?
    /// Bumped by every relayout; one that lands after a newer one started is dropped.
    @ObservationIgnored private var relayoutGeneration = 0

    /// Granularity and heuristics of what is published; a render borrows published work only when they match.
    @ObservationIgnored private var publishedGranularity: IntralineGranularity?
    @ObservationIgnored private var publishedHeuristics: DiffHeuristics?
    /// The card lists taken off screen, the latest last, kept so going back to one lends its cards again rather than
    /// rendering them all anew (book PERF-10): the whole list after a file or a folder's list showed in its place, from
    /// a closed tab or from the file list's fixed tab (book TAB-10). A render of a list takes the one with its files.
    @ObservationIgnored private var shelvedLists: [ShelvedList] = []

    /// How many card lists stay shelved: the whole list and a few folders' lists. The oldest goes first.
    package static let shelfCapacity = 3

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

    /// Options for the next renders. A change to how diffs render leaves what is published stale until `relayout`
    /// renders it again; a render in flight picks the change up by itself.
    package func configure(options: DiffRenderer.Options, context: Int, isolatesChanges: Bool) {
        if !Self.rendersAlike(options, self.options) || context != layout.context || isolatesChanges != layout.isolates
        {
            configuration += 1
        }
        self.options = options
        layout = (context, isolatesChanges)
    }

    package func clear() {
        task?.cancel()
        shelvedLists = []
        generation += 1
        completedGeneration = generation
        isRendering = false
        unpublish()
        target = nil
        error = nil
    }

    /// Renders `target`. With `keepingPublished`, what is on screen stays there, and interactive, until the whole of
    /// `target` replaces it in one step; otherwise it goes at once and `target` streams in, first file first. Either
    /// way a pair with the same path, blobs and diff options as a published one borrows its prepared diff, and its
    /// rendered file when it keeps its place under a current stamp, so the views keyed on it never rebuild.
    package func render(
        _ target: Target, left: ComparisonSource, right: ComparisonSource, granularity: IntralineGranularity,
        heuristics: DiffHeuristics, keepingPublished: Bool
    ) {
        task?.cancel()
        preparer.cancelPrefetch()
        generation += 1
        isRendering = true
        error = nil
        let inputs = RenderInputs(
            sources: Sources(left: left, right: right), granularity: granularity, heuristics: heuristics)
        let loan = self.loan(for: target, inputs: inputs)
        let keeps = keepingPublished && (file != nil || !cards.isEmpty)
        if target.isCards { shelvedLists.removeAll { $0.target.showsSameFiles(as: target) } }
        if !keeps, let published = self.target, published.isCards, !published.showsSameFiles(as: target),
            !prepared.isEmpty
        {
            shelve(published)
        }
        // A lent file drawn another way, a card becoming the whole file say, saves only its diff: streaming then puts
        // the first file on screen sooner than one step would.
        let lendsFiles = loan.rendered.contains { $0.value.stamp == currentStamp(forIndex: $0.key, in: target) }
        if !keeps {
            gapExpansions = carriedExpansions(into: target)
            unpublish()
            self.target = target
            publishedGranularity = granularity
            publishedHeuristics = heuristics
        }
        let job = RenderJob(
            target: target, inputs: inputs, generation: generation, keepingScroll: loan.sameFilePath,
            loan: keeps ? nil : loan)
        if keeps || lendsFiles {
            renderWhole(job)
        } else {
            stream(job)
        }
    }

    /// Renders everything published again, off the main actor, with the current configuration; without
    /// `keepingScroll`, every gap folds back too. A render in flight renders its own files again when it lands.
    package func relayout(keepingScroll: Bool) {
        if !keepingScroll { gapExpansions = [:] }
        refresh(keepingScroll: keepingScroll)
    }

    /// Reveals `expansion` around one gap and renders only the file it belongs to, at once on the main actor: one
    /// file's cost per drag step, and no `.finished`, since nothing else changed.
    package func setExpansion(_ expansion: GapExpansion, for key: GapKey) {
        guard self.expansion(of: key) != expansion else { return }
        gapExpansions[key] = expansion == GapExpansion() ? nil : expansion
        guard let target, prepared.indices.contains(key.fileIndex) else { return }
        rerender([key.fileIndex], of: target, keepingScroll: true)
    }

    /// Folds every revealed gap back to the context lines, keeping the scroll position.
    package func resetGaps() {
        guard !gapExpansions.isEmpty else { return }
        gapExpansions = [:]
        refresh(keepingScroll: true)
    }

    package func expansion(of key: GapKey) -> GapExpansion {
        gapExpansions[key] ?? GapExpansion()
    }

    /// Shelves what is published, the card list `published`, as the latest list, dropping the oldest past capacity.
    private func shelve(_ published: Target) {
        shelvedLists.removeAll { $0.target.showsSameFiles(as: published) }
        shelvedLists.append(
            ShelvedList(
                target: published, prepared: prepared, stamps: stamps, cards: cards.map(\.rendered),
                granularity: publishedGranularity, heuristics: publishedHeuristics))
        if shelvedLists.count > Self.shelfCapacity { shelvedLists.removeFirst(shelvedLists.count - Self.shelfCapacity) }
    }

    // MARK: Publishing

    /// Takes everything published off screen.
    private func unpublish() {
        file = nil
        cards = []
        prepared = []
        stamps = []
        publishedSources = nil
        contentVersion += 1
    }

    /// Publishes files that landed behind those already published, in target order.
    private func append(_ diffs: [PreparedDiff], _ files: [Stamped], for job: RenderJob) {
        guard job.generation == generation, let first = files.first else { return }
        let isFirst = prepared.isEmpty
        prepared += diffs
        stamps += files.map(\.stamp)
        publishedSources = job.inputs.sources
        switch job.target {
            case .file:
                PhaseTrace.log("publish file")
                var diff = first.file
                diff.keepsScrollPosition = job.keepingScroll
                file = diff
            case .cards:
                PhaseTrace.log("publish \(files.count) cards\(isFirst ? "" : " more")")
                cards += zip(diffs, files).map { RenderedFile(path: $0.title, rendered: $1.file) }
        }
        onEvent?(.published(first.file.id, isFirst: isFirst))
    }

    /// Replaces everything published with the whole of `job`'s target, in one step.
    private func publishWhole(_ diffs: [PreparedDiff], _ files: [Stamped], for job: RenderJob) {
        guard job.generation == generation, let first = files.first else { return }
        PhaseTrace.log("publish \(files.count) whole")
        gapExpansions = carriedExpansions(into: job.target)
        target = job.target
        prepared = diffs
        stamps = files.map(\.stamp)
        contentVersion += 1
        publishedSources = job.inputs.sources
        publishedGranularity = job.inputs.granularity
        publishedHeuristics = job.inputs.heuristics
        switch job.target {
            case .file:
                var diff = first.file
                diff.keepsScrollPosition = job.keepingScroll
                file = diff
                cards = []
            case .cards:
                cards = zip(diffs, files).map { RenderedFile(path: $0.title, rendered: $1.file) }
                file = nil
        }
        onEvent?(.published(first.file.id, isFirst: true))
    }

    /// Renders the published files at `indices` again, inline, under the current stamp.
    private func rerender(_ indices: [Int], of target: Target, keepingScroll: Bool) {
        let layout = renderLayout(for: target)
        let files = indices.filter { prepared.indices.contains($0) }
            .map { index -> (Int, Stamped) in
                let file = PaneRenderer.renderInline(
                    PaneRenderer.Job(index: index, diff: prepared[index]), options: options, layout: layout)
                return (index, (file, currentStamp(forIndex: index, in: target)))
            }
        install(files, of: target, keepingScroll: keepingScroll)
    }

    /// Renders again, off the main actor, every published file whose stamp is out of date, and puts each back unless
    /// something newer took its place meanwhile: a render that replaced what is published, a newer relayout, or a gap
    /// drag on that file. Sends `.finished` once it lands, unless a render is in flight, which will.
    private func refresh(keepingScroll: Bool) {
        relayoutTask?.cancel()
        relayoutGeneration += 1
        guard let target else { return }
        let stale = prepared.indices.filter { stamps[$0] != currentStamp(forIndex: $0, in: target) }
        guard !stale.isEmpty else {
            if !isRendering { onEvent?(.finished) }
            return
        }
        let relayout = relayoutGeneration
        let content = contentVersion
        let jobs = stale.map { PaneRenderer.Job(index: $0, diff: prepared[$0]) }
        let expected = stale.map { currentStamp(forIndex: $0, in: target) }
        let options = options
        let layout = renderLayout(for: target)
        relayoutTask = taskProvider.task {
            do {
                let files = try await self.renderer.render(jobs, options: options, layout: layout)
                guard relayout == self.relayoutGeneration, content == self.contentVersion, let target = self.target
                else { return }
                let landed = zip(stale, zip(files, expected))
                    .filter { index, file in file.1 == self.currentStamp(forIndex: index, in: target) }
                    .map { index, file in (index, (file.0, file.1)) }
                self.install(landed, of: target, keepingScroll: keepingScroll)
                if !self.isRendering { self.onEvent?(.finished) }
            } catch is CancellationError {
                return
            } catch {
                PhaseTrace.log("relayout failed: \(error.localizedDescription)")
            }
        }
    }

    /// Puts rendered files back at their indices of what is published, each under the stamp it was rendered with.
    private func install(_ files: [(Int, Stamped)], of target: Target, keepingScroll: Bool) {
        var updated = cards
        for (index, stamped) in files where prepared.indices.contains(index) {
            var diff = stamped.file
            diff.keepsScrollPosition = keepingScroll
            stamps[index] = stamped.stamp
            switch target {
                case .file:
                    file = diff
                case .cards:
                    guard updated.indices.contains(index) else { continue }
                    updated[index] = RenderedFile(path: updated[index].path, rendered: diff)
            }
        }
        if target.isCards { cards = updated }
    }

    private func finish(_ generation: Int) {
        guard generation == self.generation else { return }
        PhaseTrace.log("finish")
        completedGeneration = generation
        isRendering = false
        onEvent?(.finished)
    }

    private func fail(_ error: any Error, generation: Int) {
        guard generation == self.generation else { return }
        self.error = error.localizedDescription
        completedGeneration = generation
        isRendering = false
        onEvent?(.failed(error.localizedDescription))
    }

    // MARK: Stamps

    /// Whether two option sets render any diff the same way.
    private static func rendersAlike(_ lhs: DiffRenderer.Options, _ rhs: DiffRenderer.Options) -> Bool {
        lhs.granularity == rhs.granularity && lhs.palette == rhs.palette
            && lhs.lineHeightMultiple == rhs.lineHeightMultiple && lhs.sides == rhs.sides
    }

    /// Whether `target` renders its changes only, between gaps, rather than whole files.
    private func showsChangesOnly(_ target: Target) -> Bool {
        layout.isolates || target.isCards
    }

    /// A single file without a change shows whole even while changes are isolated, since its changes alone would
    /// leave the pane empty (DIFF-07); a card for such a file keeps showing nothing below its header.
    private func renderLayout(for target: Target) -> RenderLayout {
        showsChangesOnly(target)
            ? .changes(
                context: layout.context, expansions: carriedExpansions(into: target),
                wholeWhenUnchanged: !target.isCards)
            : .full
    }

    /// The stamp the file at `index` of `target` is current under.
    private func currentStamp(forIndex index: Int, in target: Target) -> Stamp {
        let changesOnly = showsChangesOnly(target)
        var expansions: [Int: GapExpansion] = [:]
        if changesOnly, carries(index, into: target) {
            for (key, expansion) in gapExpansions where key.fileIndex == index { expansions[key.gapIndex] = expansion }
        }
        return Stamp(configuration: configuration, showsChangesOnly: changesOnly, expansions: expansions)
    }

    /// The gap expansions `target` keeps: those of every file that stays at its index under the same path, even when
    /// its content changed, so revealed lines survive a reload. Gaps are matched by index, so a change that adds a
    /// hunk above an expanded gap moves its revealed lines to the gap before it.
    private func carriedExpansions(into target: Target) -> [GapKey: GapExpansion] {
        gapExpansions.filter { carries($0.key.fileIndex, into: target) }
    }

    /// Whether the file at `index` of `target` is, by path, the one published at that index.
    private func carries(_ index: Int, into target: Target) -> Bool {
        guard let published = self.target, published.pairs.indices.contains(index),
            target.pairs.indices.contains(index)
        else { return false }
        return published.pairs[index].path == target.pairs[index].path
    }

    /// A renderer that answered fewer panes than it was given diffs.
    private struct IncompleteRender: LocalizedError {
        var errorDescription: String? { "The diff could not be rendered." }
    }
}

/// How a render gets from its target to what it publishes, borrowing from the published state what it can.
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

    /// What the published state lends a render: prepared diffs by identity, and the rendered files that keep their
    /// place and identity, with the stamps they were rendered under.
    private struct Loan {
        var preparedByIdentity: [PairIdentity: PreparedDiff] = [:]
        var rendered: [Int: Stamped] = [:]
        /// Whether the published target was a file at the same path, whatever its blobs, so a reload keeps the scroll.
        var sameFilePath = false
    }

    /// A card list taken off screen: its target, its prepared diffs and rendered cards in target order, the stamps they
    /// were rendered under, and the diff options they were prepared with.
    private struct ShelvedList {
        let target: Target
        let prepared: [PreparedDiff]
        let stamps: [Stamp]
        let cards: [RenderedDiff]
        let granularity: IntralineGranularity?
        let heuristics: DiffHeuristics?
    }

    /// One render: its target, what it compares, and what it borrowed from the published state when it started.
    private struct RenderJob {
        let target: Target
        let inputs: RenderInputs
        let generation: Int
        let keepingScroll: Bool
        /// What a render that takes the published state off screen borrowed from it first; nil for a render that keeps
        /// it, which borrows from whatever is on screen when it lands.
        let loan: Loan?
    }

    /// What the published state lends a render of `target`; nothing when the granularity or heuristics differ. A
    /// render still streaming lends the prefix that landed.
    private func loan(for target: Target, inputs: RenderInputs) -> Loan {
        var loan = Loan()
        guard let published = self.target else { return loan }
        if case .file(let old) = published, case .file(let new) = target { loan.sameFilePath = old.path == new.path }
        if inputs.granularity == publishedGranularity, inputs.heuristics == publishedHeuristics {
            lend(prepared, from: published, rendered: publishedFile(at:), stamps: stamps, to: target, into: &loan)
        }
        // A list goes back to the shelved list with the same files, else to the latest shelved, a list that has
        // gained or lost a file since, when that list was prepared the same way. Lent last, so its cards take the place
        // of the file drawn whole that the published state lends at the same index.
        if target.isCards,
            let shelf = shelvedLists.last(where: { $0.target.showsSameFiles(as: target) }) ?? shelvedLists.last,
            inputs.granularity == shelf.granularity, inputs.heuristics == shelf.heuristics
        {
            let cards = shelf.cards
            lend(
                shelf.prepared, from: shelf.target, rendered: { cards.indices.contains($0) ? cards[$0] : nil },
                stamps: shelf.stamps, to: target, into: &loan)
        }
        return loan
    }

    /// Adds to `loan` what `prepared`, the diffs of `source` in order, lends a render of `target`: every reusable
    /// diff by identity, and each rendered file that keeps its place, with the stamp it was rendered under.
    private func lend(
        _ prepared: [PreparedDiff], from source: Target, rendered: (Int) -> RenderedDiff?, stamps: [Stamp],
        to target: Target, into loan: inout Loan
    ) {
        let oldPairs = source.pairs
        let newPairs = target.pairs
        for index in prepared.indices where index < oldPairs.count {
            let identity = PairIdentity(oldPairs[index])
            guard identity.isReusable else { continue }
            loan.preparedByIdentity[identity] = prepared[index]
            // A card's rows bake in its file index, which hover maps hits back by, so only a pair that kept its place
            // lends its rendered file.
            guard index < newPairs.count, PairIdentity(newPairs[index]) == identity,
                let file = rendered(index), stamps.indices.contains(index)
            else { continue }
            loan.rendered[index] = (file, stamps[index])
        }
    }

    /// The published file or card at `index`.
    private func publishedFile(at index: Int) -> RenderedDiff? {
        switch target {
            case .file: index == 0 ? file : nil
            case .cards: cards.indices.contains(index) ? cards[index].rendered : nil
            case nil: nil
        }
    }

    /// Publishes `job`'s first file as soon as it lands, at once when it is cached, then the rest in one batch behind
    /// it. What was published went at the start.
    private func stream(_ job: RenderJob) {
        let pairs = job.target.pairs
        var headLanded = false
        if let head = pairs.first,
            let diff = job.loan?.preparedByIdentity[PairIdentity(head)]
                ?? preparer.cached(head, granularity: job.inputs.granularity, heuristics: job.inputs.heuristics)
        {
            let stamp = currentStamp(forIndex: 0, in: job.target)
            let file = PaneRenderer.renderInline(
                PaneRenderer.Job(index: 0, diff: diff), options: options, layout: renderLayout(for: job.target))
            append([diff], [(file, stamp)], for: job)
            headLanded = true
            if pairs.count == 1 {
                finish(job.generation)
                return
            }
        }
        task = taskProvider.task {
            do {
                if !headLanded { try await self.prepareAndAppend(0 ..< 1, for: job) }
                if pairs.count > 1 { try await self.prepareAndAppend(1 ..< pairs.count, for: job) }
                self.finish(job.generation)
            } catch is CancellationError {
                return
            } catch {
                self.fail(error, generation: job.generation)
            }
        }
    }

    /// Prepares the pairs of `job`'s target at `indices`, renders them until current, and publishes them behind what
    /// landed before them.
    private func prepareAndAppend(_ indices: Range<Int>, for job: RenderJob) async throws {
        let diffs = try await prepare(Array(indices), for: job)
        let jobs = zip(indices, diffs).map { PaneRenderer.Job(index: $0, diff: $1) }
        let files = try await renderCurrent(jobs, for: job)
        append(diffs, files, for: job)
    }

    /// Renders the whole of `job`'s target and publishes it in one step, borrowing every file the published state
    /// lends under a current stamp; at once when it lends them all.
    private func renderWhole(_ job: RenderJob) {
        let loan = job.loan ?? self.loan(for: job.target, inputs: job.inputs)
        let pairs = job.target.pairs
        let diffs = pairs.compactMap { loan.preparedByIdentity[PairIdentity($0)] }
        if diffs.count == pairs.count,
            pairs.indices.allSatisfy({ loan.rendered[$0]?.stamp == currentStamp(forIndex: $0, in: job.target) })
        {
            publishWhole(diffs, pairs.indices.compactMap { loan.rendered[$0] }, for: job)
            finish(job.generation)
            return
        }
        task = taskProvider.task {
            do {
                let diffs = try await self.prepare(Array(pairs.indices), for: job)
                try await self.completeWhole(job, diffs: diffs)
            } catch is CancellationError {
                return
            } catch {
                self.fail(error, generation: job.generation)
            }
        }
    }

    /// Renders every file of `job`'s target the published state no longer lends under a current stamp, again for any
    /// whose stamp moved on while it rendered, then publishes the whole target. What is lent is decided when the
    /// render lands, from what is on screen then, so a gap drag or a relayout meanwhile is never lost.
    private func completeWhole(_ job: RenderJob, diffs: [PreparedDiff]) async throws {
        var results: [Int: Stamped] = [:]
        while true {
            let lent = (job.loan ?? loan(for: job.target, inputs: job.inputs)).rendered
            var files: [Stamped] = []
            var stale: [PaneRenderer.Job] = []
            for (index, diff) in diffs.enumerated() {
                let current = currentStamp(forIndex: index, in: job.target)
                if let file = lent[index], file.stamp == current {
                    files.append(file)
                } else if let file = results[index], file.stamp == current {
                    files.append(file)
                } else {
                    stale.append(PaneRenderer.Job(index: index, diff: diff))
                }
            }
            guard !stale.isEmpty else {
                publishWhole(diffs, files, for: job)
                finish(job.generation)
                return
            }
            for (index, file) in try await renderStep(stale, for: job) { results[index] = file }
        }
    }

    /// Renders `jobs` off the main actor, again for any whose stamp moved on while they rendered, so a relayout or a
    /// gap drag meanwhile is never lost; returns each rendered under the stamp still current when it lands.
    private func renderCurrent(_ jobs: [PaneRenderer.Job], for job: RenderJob) async throws -> [Stamped] {
        var results: [Int: Stamped] = [:]
        while true {
            let stale = jobs.filter { results[$0.index]?.stamp != currentStamp(forIndex: $0.index, in: job.target) }
            guard !stale.isEmpty else { break }
            for (index, file) in try await renderStep(stale, for: job) { results[index] = file }
        }
        return jobs.compactMap { results[$0.index] }
    }

    /// One render step: `jobs` rendered off the main actor with the options and expansions current as it starts, each
    /// with the stamp it was rendered under.
    private func renderStep(_ jobs: [PaneRenderer.Job], for job: RenderJob) async throws -> [(Int, Stamped)] {
        let stamps = jobs.map { currentStamp(forIndex: $0.index, in: job.target) }
        let files = try await renderer.render(jobs, options: options, layout: renderLayout(for: job.target))
        guard job.generation == generation else { throw CancellationError() }
        guard files.count == jobs.count else { throw IncompleteRender() }
        return zip(jobs, zip(files, stamps)).map { ($0.index, ($1.0, $1.1)) }
    }

    /// The prepared diffs of `job`'s target at `indices`: borrowed from the published state, else cached or read and
    /// diffed now.
    private func prepare(_ indices: [Int], for job: RenderJob) async throws -> [PreparedDiff] {
        let pairs = job.target.pairs
        let loan = job.loan ?? self.loan(for: job.target, inputs: job.inputs)
        var diffs: [Int: PreparedDiff] = [:]
        for index in indices { diffs[index] = loan.preparedByIdentity[PairIdentity(pairs[index])] }
        let missing = indices.filter { diffs[$0] == nil }
        if !missing.isEmpty {
            let fresh = try await preparer.prepare(
                missing.map { pairs[$0] }, left: job.inputs.sources.left, right: job.inputs.sources.right,
                granularity: job.inputs.granularity, heuristics: job.inputs.heuristics)
            guard job.generation == generation else { throw CancellationError() }
            for (index, diff) in zip(missing, fresh) { diffs[index] = diff }
        }
        let ordered = indices.compactMap { diffs[$0] }
        guard ordered.count == indices.count else { throw IncompleteRender() }
        return ordered
    }
}

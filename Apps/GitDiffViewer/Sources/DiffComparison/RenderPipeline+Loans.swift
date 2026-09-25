import AemiCore
import DiffCore
import DiffGit
import DiffRendering
import Foundation
import Observation

/// How a render gets from its target to what it publishes, borrowing from the published state what it can.
extension RenderPipeline {
    /// A pair's rendering identity: its path and both blob ids. Pairs with the same identity produce the same diff.
    struct PairIdentity: Hashable {
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
    struct Loan {
        var preparedByIdentity: [PairIdentity: PreparedDiff] = [:]
        var rendered: [Int: Stamped] = [:]
        /// Whether the published target was a file at the same path, whatever its blobs, so a reload keeps the scroll.
        var sameFilePath = false
    }

    /// A card list taken off screen: its target, its prepared diffs and rendered cards in target order, the stamps they
    /// were rendered under, and the diff options they were prepared with.
    struct ShelvedList {
        let target: Target
        let prepared: [PreparedDiff]
        let stamps: [Stamp]
        let cards: [RenderedDiff]
        let granularity: IntralineGranularity?
        let heuristics: DiffHeuristics?
    }

    /// One render: its target, what it compares, and what it borrowed from the published state when it started.
    struct RenderJob {
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
    func loan(for target: Target, inputs: RenderInputs) -> Loan {
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
    func lend(
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
    func publishedFile(at index: Int) -> RenderedDiff? {
        switch target {
            case .file: index == 0 ? file : nil
            case .cards: cards.indices.contains(index) ? cards[index].rendered : nil
            case nil: nil
        }
    }

    /// Publishes `job`'s first file as soon as it lands, at once when it is cached, then the rest in one batch behind
    /// it. What was published went at the start.
    func stream(_ job: RenderJob) {
        let pairs = job.target.pairs
        var headLanded = false
        if let head = pairs.first,
            let diff = job.loan?.preparedByIdentity[PairIdentity(head)]
                ?? preparer.cached(head, granularity: job.inputs.granularity, heuristics: job.inputs.heuristics)
        {
            let stamp = currentStamp(forIndex: 0, in: job.target)
            let file = PaneRenderer.renderInline(
                PaneRenderer.Job(index: 0, diff: diff), options: renderOptions(for: job.target),
                layout: renderLayout(for: job.target))
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
    func prepareAndAppend(_ indices: Range<Int>, for job: RenderJob) async throws {
        let diffs = try await prepare(Array(indices), for: job)
        let jobs = zip(indices, diffs).map { PaneRenderer.Job(index: $0, diff: $1) }
        let files = try await renderCurrent(jobs, for: job)
        append(diffs, files, for: job)
    }

    /// Renders the whole of `job`'s target and publishes it in one step, borrowing every file the published state
    /// lends under a current stamp; at once when it lends them all.
    func renderWhole(_ job: RenderJob) {
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
    func completeWhole(_ job: RenderJob, diffs: [PreparedDiff]) async throws {
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
    func renderCurrent(_ jobs: [PaneRenderer.Job], for job: RenderJob) async throws -> [Stamped] {
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
    func renderStep(_ jobs: [PaneRenderer.Job], for job: RenderJob) async throws -> [(Int, Stamped)] {
        let stamps = jobs.map { currentStamp(forIndex: $0.index, in: job.target) }
        let files = try await renderer.render(
            jobs, options: renderOptions(for: job.target), layout: renderLayout(for: job.target))
        guard job.generation == generation else { throw CancellationError() }
        guard files.count == jobs.count else { throw IncompleteRender() }
        return zip(jobs, zip(files, stamps)).map { ($0.index, ($1.0, $1.1)) }
    }

    /// The prepared diffs of `job`'s target at `indices`: borrowed from the published state, else cached or read and
    /// diffed now.
    func prepare(_ indices: [Int], for job: RenderJob) async throws -> [PreparedDiff] {
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

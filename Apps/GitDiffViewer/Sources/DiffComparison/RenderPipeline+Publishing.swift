import AemiCore
import DiffCore
import DiffGit
import DiffRendering
import Foundation
import Observation

/// How a render reaches the model: publishing what landed, rendering it again, and ending the render.
extension RenderPipeline {
    /// Shelves what is published, the card list `published`, as the latest list, dropping the oldest past capacity.
    func shelve(_ published: Target) {
        shelvedLists.removeAll { $0.target.showsSameFiles(as: published) }
        shelvedLists.append(
            ShelvedList(
                target: published, prepared: prepared, stamps: stamps, cards: cards.map(\.rendered),
                granularity: publishedGranularity, heuristics: publishedHeuristics))
        if shelvedLists.count > Self.shelfCapacity { shelvedLists.removeFirst(shelvedLists.count - Self.shelfCapacity) }
    }

    // MARK: Publishing

    /// Takes everything published off screen.
    func unpublish() {
        file = nil
        cards = []
        prepared = []
        stamps = []
        publishedSources = nil
        contentVersion += 1
    }

    /// Publishes files that landed behind those already published, in target order.
    func append(_ diffs: [PreparedDiff], _ files: [Stamped], for job: RenderJob) {
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
    func publishWhole(_ diffs: [PreparedDiff], _ files: [Stamped], for job: RenderJob) {
        guard job.generation == generation, let first = files.first else { return }
        PhaseTrace.log("publish \(files.count) whole")
        gapExpansions = carriedExpansions(into: job.target)
        disclosedChanges = carriedDisclosures(into: job.target)
        target = job.target
        targetVersion &+= 1
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
    func rerender(_ indices: [Int], of target: Target, keepingScroll: Bool) {
        let layout = renderLayout(for: target)
        let files = indices.filter { prepared.indices.contains($0) }
            .map { index -> (Int, Stamped) in
                let file = PaneRenderer.renderInline(
                    PaneRenderer.Job(index: index, diff: prepared[index]), options: renderOptions(for: target),
                    layout: layout)
                return (index, (file, currentStamp(forIndex: index, in: target)))
            }
        install(files, of: target, keepingScroll: keepingScroll)
    }

    /// Renders again, off the main actor, every published file whose stamp is out of date, and puts each back unless
    /// something newer took its place meanwhile: a render that replaced what is published, a newer relayout, or a gap
    /// drag on that file. Sends `.finished` once it lands, unless a render is in flight, which will.
    func refresh(keepingScroll: Bool) {
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
        let options = renderOptions(for: target)
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
    func install(_ files: [(Int, Stamped)], of target: Target, keepingScroll: Bool) {
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

    func finish(_ generation: Int) {
        guard generation == self.generation else { return }
        PhaseTrace.log("finish")
        completedGeneration = generation
        isRendering = false
        onEvent?(.finished)
    }

    func fail(_ error: any Error, generation: Int) {
        guard generation == self.generation else { return }
        self.error = error.localizedDescription
        completedGeneration = generation
        isRendering = false
        onEvent?(.failed(error.localizedDescription))
    }
}

import AemiCore
import DiffCore
import DiffRendering
import Foundation

/// The emphasis and moved lines of a displayed file (PERF-09 stage 2): the diff's second and third phases, run off the
/// main actor once a pane shows the file, the moved lines first, then the emphasis of the changes the panes show, then
/// the rest in chunks, each landing as it is found, the whole within ``marksDeadline``.
extension RenderPipeline {
    /// Finds `file`'s moved lines and emphasis, unless they are found or being found, or it has no change.
    func startMarks(of file: PublishedFile) {
        let diff = file.diff
        guard !decorator.isMarked(diff.id), !diff.model.structure.changes.isEmpty else { return }
        let first = visibleChanges(of: file)
        let stamp = DiffDecorator.Stamp(generation: generation, fileID: file.rendered.id)
        let clock = decorator.clock
        decorator.trackMarks(
            taskProvider.task(priority: .utility) {
                await Self.findMarks(of: diff, first: first, clock: clock) { found in
                    await self.land(found, for: diff.id, stamp: stamp)
                }
                self.decorator.endMarks(diff.id, cancelled: Task.isCancelled)
            }, for: diff.id)
    }

    /// The changes of `file` whose lines a pane shows, or that lie around the first change when none reports its rows.
    func visibleChanges(of file: PublishedFile) -> [Int] {
        let diff = file.diff
        let old = visibleLines(of: .old, in: file) ?? Self.linesAroundFirstChange(of: .old, in: diff)
        let new = visibleLines(of: .new, in: file) ?? Self.linesAroundFirstChange(of: .new, in: diff)
        let changes = diff.model.structure.changes
        return changes.indices.filter { changes[$0].old.overlaps(old) || changes[$0].new.overlaps(new) }
    }

    /// Takes what a marks job found, unless its job was cancelled, or its render was superseded and no published file
    /// shows its preparation any more; then decorates every published text that shows it.
    private func land(_ found: MarksFound, for preparation: UUID, stamp: DiffDecorator.Stamp) {
        let files = publishedFiles()
        let shows = { (file: PublishedFile) in file.diff.id == preparation }
        guard !Task.isCancelled, stamp.generation == generation || files.contains(where: shows) else { return }
        decorator.land(found, for: preparation)
        decorator.publish(files.map { ($0.rendered, $0.composition) })
        sendDecorated(.marks, where: shows)
    }

    /// Finds `diff`'s marks, `first` changes first, handing each chunk to `land`, until they are all found or
    /// ``marksDeadline`` passes on `clock`, whichever comes first.
    @concurrent
    static func findMarks(
        of diff: PreparedDiff, first: [Int], clock: any Clock<Duration>,
        land: @escaping @Sendable (MarksFound) async -> Void
    ) async {
        await withinDeadline(marksDeadline, on: clock) { await findEveryMark(of: diff, first: first, land: land) }
    }

    /// Runs `work` until it ends or `deadline` passes on `clock`, whichever comes first; past the deadline `work` is
    /// cancelled, and keeps whatever it handed on before.
    nonisolated static func withinDeadline(
        _ deadline: Duration, on clock: any Clock<Duration>, _ work: @escaping @Sendable () async -> Void
    ) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await work() }
            group.addTask { try? await clock.sleep(for: deadline) }
            // The first child to end, the work or its deadline, ends the other.
            await group.next()
            group.cancelAll()
        }
    }

    /// The moved lines, then the emphasis of `first`, then of the other changes a chunk at a time; stops at the first
    /// check after its task is cancelled.
    private nonisolated static func findEveryMark(
        of diff: PreparedDiff, first: [Int], land: @Sendable (MarksFound) async -> Void
    ) async {
        let model = diff.model
        let structure = model.structure
        if diff.pipeline.detectsMovedBlocks { await land(MarksFound(moved: MovedBlocks.detect(in: structure))) }
        let isFirst = Set(first)
        let rest = structure.changes.indices.filter { !isFirst.contains($0) }
        var chunks = first.isEmpty ? [] : [first]
        chunks += stride(from: 0, to: rest.count, by: marksChunk)
            .map { Array(rest[$0 ..< min($0 + marksChunk, rest.count)]) }
        let old = SubstringLines(model.oldLines)
        let new = SubstringLines(model.newLines)
        let tokens: (any IntralineTokenSource)? = diff.granularity == .syntax ? diff.tokenSource : nil
        for chunk in chunks {
            guard
                let emphasis = try? await IntralineEmphasis.emphasis(
                    for: chunk, in: structure, pairs: model.changePairs, old: old, new: new,
                    granularity: diff.granularity, refiners: diff.pipeline.intralineRefiners, tokens: tokens)
            else { return }
            await land(byLine(emphasis, in: model))
        }
    }

    /// `emphasis`, by change, as each side's emphasis by source line.
    private nonisolated static func byLine(_ emphasis: [Int: ChangeEmphasis], in model: DiffModel) -> MarksFound {
        var found = MarksFound()
        for (index, change) in emphasis {
            let lines = model.structure.changes[index]
            for (pair, line) in zip(model.changePairs[index], change.lines) {
                guard let line, let old = pair.old, let new = pair.new else { continue }
                found.old[lines.old.lowerBound + old] = line.old
                found.new[lines.new.lowerBound + new] = line.new
            }
        }
        return found
    }
}

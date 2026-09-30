import AemiCore
import DiffCore
import DiffGit
import DiffRendering
import Foundation
import Observation

/// What a published file was rendered under, and whether that is still current.
extension RenderPipeline {
    /// Whether two option sets render any diff the same way.
    static func rendersAlike(_ lhs: DiffRenderer.Options, _ rhs: DiffRenderer.Options) -> Bool {
        lhs.granularity == rhs.granularity && lhs.palette == rhs.palette
            && lhs.lineHeightMultiple == rhs.lineHeightMultiple && lhs.sides == rhs.sides
            && lhs.compactsInline == rhs.compactsInline
    }

    /// Whether `target` renders its changes only, between gaps, rather than whole files.
    func showsChangesOnly(_ target: Target) -> Bool {
        layout.isolates || target.isCards
    }

    /// A single file without a change shows whole even while changes are isolated, since its changes alone would
    /// leave the pane empty (DIFF-07); a card for such a file keeps showing nothing below its header.
    func renderLayout(for target: Target) -> RenderLayout {
        showsChangesOnly(target)
            ? .changes(
                context: layout.context, expansions: carriedExpansions(into: target),
                wholeWhenUnchanged: !target.isCards)
            : .full
    }

    /// The stamp the file at `index` of `target` is current under.
    func currentStamp(forIndex index: Int, in target: Target) -> Stamp {
        let changesOnly = showsChangesOnly(target)
        var expansions: [Int: GapExpansion] = [:]
        if changesOnly, carries(index, into: target) {
            for (key, expansion) in gapExpansions where key.fileIndex == index { expansions[key.gapIndex] = expansion }
        }
        let disclosed =
            carries(index, into: target)
            ? Set(disclosedChanges.filter { $0.fileIndex == index }.map(\.changeIndex)) : []
        let folds = carries(index, into: target) ? foldedScopes.filter { $0.key.fileIndex == index } : [:]
        return Stamp(
            configuration: configuration, showsChangesOnly: changesOnly, expansions: expansions, disclosed: disclosed,
            folds: folds)
    }

    /// The gap expansions `target` keeps: those of every file that stays at its index under the same path, even when
    /// its content changed, so revealed lines survive a reload. Gaps are matched by index, so a change that adds a
    /// hunk above an expanded gap moves its revealed lines to the gap before it.
    func carriedExpansions(into target: Target) -> [GapKey: GapExpansion] {
        gapExpansions.filter { carries($0.key.fileIndex, into: target) }
    }

    /// Whether the file at `index` of `target` is, by path, the one published at that index.
    func carries(_ index: Int, into target: Target) -> Bool {
        guard let published = self.target, published.pairs.indices.contains(index),
            target.pairs.indices.contains(index)
        else { return false }
        return published.pairs[index].path == target.pairs[index].path
    }

    /// A renderer that answered fewer panes than it was given diffs.
    struct IncompleteRender: LocalizedError {
        var errorDescription: String? { "The diff could not be rendered." }
    }
}

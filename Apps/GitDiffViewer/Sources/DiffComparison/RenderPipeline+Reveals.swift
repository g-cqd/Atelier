package import DiffCore
import DiffGit
package import DiffRendering

/// What the user reveals of what is published: the rows around a gap (book DIFF-02), the changes the compact inline
/// view discloses (book DIFF-04), and the scopes folded (DIFF-03), kept alike.
extension RenderPipeline {
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

    /// Every change of the published files at `indices`, in the inline layout (book DIFF-04).
    package func changeKeys(ofFiles indices: [Int]) -> [ChangeKey] {
        indices.filter { prepared.indices.contains($0) }
            .flatMap { index in
                prepared[index].model.unifiedChangeRanges.indices.map { ChangeKey(fileIndex: index, changeIndex: $0) }
            }
    }

    /// Shows disclosed exactly the changes of `keys` among those of the files at `indices`, folding the others, and
    /// renders again the files whose changes it discloses or folds, keeping the scroll position (book DIFF-04). One
    /// file renders at once, as a gap drag does; more render off the main actor.
    package func setDisclosedChanges(_ keys: Set<ChangeKey>, ofFiles indices: Set<Int>) {
        let kept = disclosedChanges.filter { !indices.contains($0.fileIndex) }
        let updated = kept.union(keys.filter { indices.contains($0.fileIndex) })
        guard updated != disclosedChanges else { return }
        let changed = Set(updated.symmetricDifference(disclosedChanges).map(\.fileIndex))
        disclosedChanges = updated
        guard let target else { return }
        if changed.count == 1, let index = changed.first, prepared.indices.contains(index) {
            rerender([index], of: target, keepingScroll: true)
        } else {
            refresh(keepingScroll: true)
        }
    }

    /// The options `target` renders with: the configured ones, and the changes it keeps disclosed.
    func renderOptions(for target: Target) -> DiffRenderer.Options {
        var options = options
        options.disclosedChanges = carriedDisclosures(into: target)
        options.foldedScopes = carriedFolds(into: target)
        return options
    }

    /// The folded scopes `target` keeps, as ``carriedExpansions(into:)`` keeps revealed lines (DIFF-03).
    func carriedFolds(into target: Target) -> [ScopeFoldKey: Int] {
        foldedScopes.filter { carries($0.key.fileIndex, into: target) }
    }

    /// Keeps folded the folds of the files `target` carries whose side is the same blob as the one published, and
    /// holds back every other fold it carries until that side's scopes land (``settlePendingFolds()``): a fold never
    /// hides rows that no longer make up its scope. A side without a blob id, as a working tree's, is held back too.
    func holdFolds(forContentOf target: Target) {
        var kept: [ScopeFoldKey: Int] = [:]
        var held: [ScopeFoldKey: Int] = [:]
        for (key, last) in foldedScopes.merging(pendingFolds, uniquingKeysWith: { folded, _ in folded })
        where carries(key.fileIndex, into: target) {
            if foldedScopes[key] != nil, sameContent(on: key, in: target) { kept[key] = last } else { held[key] = last }
        }
        foldedScopes = kept
        pendingFolds = held
    }

    /// Whether the side of `key`'s file in `target` is the blob published there.
    private func sameContent(on key: ScopeFoldKey, in target: Target) -> Bool {
        guard let published = self.target else { return false }
        let entry = { (pair: FilePair) in key.isOld ? pair.old?.blobID : pair.new?.blobID }
        guard let blob = entry(published.pairs[key.fileIndex]) else { return false }
        return entry(target.pairs[key.fileIndex]) == blob
    }

    /// Folds again each held-back fold whose side's scopes have landed, when its first line still opens a scope that
    /// reaches at least as far, down to that scope's end, and drops the others.
    func settlePendingFolds() {
        guard !pendingFolds.isEmpty else { return }
        var settled: [ScopeFoldKey: Int] = [:]
        var resolved: [ScopeFoldKey] = []
        for (index, file) in publishedFiles().enumerated() {
            let text = [file.rendered.unified, file.rendered.new, file.rendered.old].compactMap(\.self).first
            guard let text, let decorations = decorator.byText[text.id] else { continue }
            for (key, last) in pendingFolds where key.fileIndex == index {
                guard let scopes = (key.isOld ? decorations.old : decorations.new).scopes else { continue }
                resolved.append(key)
                let scope = scopes.scopes.first { $0.lines.lowerBound == key.firstLine && $0.lines.upperBound >= last }
                if let scope { settled[key] = scope.lines.upperBound }
            }
        }
        for key in resolved { pendingFolds[key] = nil }
        if !settled.isEmpty { changeFolds(.fold(settled)) }
    }

    /// Folds or unfolds scopes as `request` asks, and renders again the files whose folds changed, keeping the scroll
    /// position (DIFF-03): one file at once, as a gap drag does, more off the main actor. Colour, emphasis and the
    /// ribbon come back at once, since every decoration is kept by source line.
    package func changeFolds(_ request: ScopeFoldRequest) {
        var updated = foldedScopes
        switch request {
            case .fold(let folds): updated.merge(folds) { $1 }
            case .unfold(let keys): for key in keys { updated[key] = nil }
        }
        guard updated != foldedScopes else { return }
        let changed = Set(
            Set(updated.keys).symmetricDifference(foldedScopes.keys).map(\.fileIndex)
                + updated.filter { foldedScopes[$0.key] != $0.value }.map(\.key.fileIndex))
        foldedScopes = updated
        guard let target else { return }
        if changed.count == 1, let index = changed.first, prepared.indices.contains(index) {
            rerender([index], of: target, keepingScroll: true)
        } else {
            refresh(keepingScroll: true)
        }
    }

    /// The disclosed changes `target` keeps, as ``carriedExpansions(into:)`` keeps revealed lines: those of every file
    /// that stays at its index under the same path. Changes are matched by their place among the file's changes.
    func carriedDisclosures(into target: Target) -> Set<ChangeKey> {
        disclosedChanges.filter { carries($0.fileIndex, into: target) }
    }
}

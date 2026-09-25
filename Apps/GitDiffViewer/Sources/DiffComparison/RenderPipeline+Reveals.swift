package import DiffCore
package import DiffRendering

/// What the user reveals of what is published: the rows around a gap (book DIFF-02), and the changes the compact
/// inline view discloses (book DIFF-04), kept alike.
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
        return options
    }

    /// The disclosed changes `target` keeps, as ``carriedExpansions(into:)`` keeps revealed lines: those of every file
    /// that stays at its index under the same path. Changes are matched by their place among the file's changes.
    func carriedDisclosures(into target: Target) -> Set<ChangeKey> {
        disclosedChanges.filter { carries($0.fileIndex, into: target) }
    }
}

package import DiffCore
package import DiffRendering

/// What the user reveals of what is published: the rows around a gap (book DIFF-02).
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
}

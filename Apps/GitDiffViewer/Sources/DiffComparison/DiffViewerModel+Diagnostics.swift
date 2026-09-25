import AemiCore
package import AtelierDiagnostics
import AtelierDocIndex
package import AtelierLSP
import Darwin
import DiffCore
import DiffGit
import DiffRendering
import Foundation

/// Diagnostics and hover documentation wiring for ``DiffViewerModel``.
extension DiffViewerModel {
    // MARK: Diagnostics

    /// Builds this window's ``DiagnosticsModel`` over `engine` and `settings`; diagnostics stay idle unless the right
    /// side is a directory.
    package func attachDiagnostics(engine: DiagnosticsEngine, settings: ViewerSettings) {
        let diagnosticsModel = DiagnosticsModel(engine: engine, settings: settings, taskProvider: taskProvider)
        diagnosticsModel.onFindingsChanged = { [weak self] _ in self?.diagnosticsVersion &+= 1 }
        diagnostics = diagnosticsModel
    }

    /// Maps each rendered row's `fileIndex` to the path its findings are keyed under, from the pairs behind the
    /// current render target.
    package var diagnosticFilePaths: [Int: String] { diagnosticFilePathMaps.right }

    /// Both sides' file-index-to-path maps of the current render target, built once per target: every pane reads
    /// them on every findings change, so building them per read costs a card list the square of its card count. A
    /// commit group's own change keeps only the sides it shares with the comparison, the only ones analyzed: the
    /// working tree's under Uncommitted Changes, none under a commit (D39).
    /// - Complexity: O(1) while the target is unchanged, O(files) after it changes.
    package var diagnosticFilePathMaps: DiagnosticFilePaths {
        let scope = commitScope
        if let cache = diagnosticFilePathCache, cache.targetVersion == pipeline.targetVersion,
            cache.scope == scope?.key
        {
            return cache.paths
        }
        var paths = DiagnosticFilePaths(for: pipeline.target?.pairs ?? [])
        if let scope {
            paths = DiagnosticFilePaths(
                right: scope.right == right.source ? paths.right : [:],
                left: scope.left == left.source ? paths.left : [:])
        }
        diagnosticFilePathCache = (pipeline.targetVersion, scope?.key, paths)
        diagnosticFilePathBuilds += 1
        return paths
    }

    // MARK: Hover documentation

    /// Builds this window's hover documentation: a doc-comment index shared by every pane, tiered behind
    /// `lspRegistry` for on-disk files on the new side. It indexes only while the setting shows hover
    /// documentation, and indexes the comparison on screen when the setting turns it on. Once the user trusts the
    /// repository shown on the right in `trust`, the displayed sides ask for semantic colour again
    /// (``retrySemanticColor(afterTrusting:)``); hovers ask its language servers from then on by themselves.
    package func attachHoverDocs(lspRegistry: LanguageServerRegistry?, trust: RepositoryTrust? = nil) {
        semanticColor.registry = lspRegistry
        trust?
            .addDecisionObserver(self) { [weak self] root, decision in
                guard decision == .trusted else { return }
                self?.retrySemanticColor(afterTrusting: root)
            }
        let hoverDocs = HoverDocumentationModel(
            lspRegistry: lspRegistry, taskProvider: taskProvider, index: DocCommentIndex(store: syntaxFacts),
            symbolKinds: syntaxFacts)
        hoverDocs.isEnabled = settings.showsHoverDocumentation
        self.hoverDocs = hoverDocs
        // The setting is an appearance change, which the model's own observer passes over.
        settings.addObserver(self) { [weak self] _ in self?.followHoverDocumentationSetting() }
    }

    /// Turns ``hoverDocs`` on or off with the setting, feeding it the comparison on screen when it turns on.
    private func followHoverDocumentationSetting() {
        guard let hoverDocs, hoverDocs.isEnabled != settings.showsHoverDocumentation else { return }
        hoverDocs.isEnabled = settings.showsHoverDocumentation
        updateHoverDocs()
    }

    /// Feeds ``hoverDocs`` both sides of every file prepared so far behind the render target, and the on-disk root of
    /// the right side shown when there is one; nothing while hover documentation is off.
    func updateHoverDocs() {
        guard let hoverDocs, hoverDocs.isEnabled else { return }
        let allPairs = pipeline.target?.pairs ?? []
        let prepared = pipeline.prepared
        // Feed the prefix that landed: waiting for every card would starve the index until the last one lands.
        let pairs = allPairs.prefix(prepared.count)
        guard !pairs.isEmpty else { return }
        // The new side's own source: a commit's change shown under the grouping by commit is read from git, and has
        // no on-disk root for a language server even when the comparison's right side is the working tree.
        let shownRight = commitScope?.right ?? right.source
        let root: URL? = if case .directory(let rightRoot) = shownRight { rightRoot } else { nil }
        let files = zip(pairs.indices, zip(pairs, prepared))
            .map { index, pair in
                let (filePair, diff) = pair
                return HoverDocumentationModel.FileEntry(
                    index: index, leftPath: filePair.path, rightPath: filePair.new?.relativePath,
                    oldText: diff.model.oldText, newText: diff.model.newText, oldBlobID: filePair.old?.blobID,
                    newBlobID: filePair.new?.blobID)
            }
        hoverDocs.comparisonChanged(
            root: root, files: files, corpusReader: reader, corpusSource: right.source, corpusEntries: right.entries)
    }

    /// The severity counts of the file at `leftPath`: the right side's findings, keyed by its right path, and the left
    /// side's, keyed by `leftPath`, whichever sides were analyzed.
    package func diagnosticSeverityCounts(for leftPath: String) -> DiagnosticSeverityCounts {
        if let scope = commitScope, let file = scope.file(atPath: leftPath) {
            // Only a side the comparison shares with the change shown was analyzed, and its findings apply.
            let rightPath = scope.right == right.source ? file.pair.new?.relativePath : nil
            let leftPath = scope.left == left.source ? file.pair.old?.relativePath : nil
            let rightFindings = rightPath.flatMap { diagnostics?.findingsByFile[$0] } ?? []
            let leftFindings = leftPath.flatMap { diagnostics?.leftFindingsByFile[$0] } ?? []
            return DiagnosticSeverityCounts(rightFindings + leftFindings)
        }
        let right = diagnostics?.findingsByFile[counterpartPath(of: leftPath, in: .left)] ?? []
        let left = diagnostics?.leftFindingsByFile[leftPath] ?? []
        return DiagnosticSeverityCounts(right + left)
    }

    /// Tells ``diagnostics`` what each side of the comparison offers the analyzers (DIAG-08, D12).
    func updateDiagnostics() {
        updateAnalyzedSides()
    }
}

import AemiCore
package import AtelierDiagnostics
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
    package var diagnosticFilePaths: [Int: String] {
        DiagnosticFileIndex.paths(for: pipeline.target?.pairs ?? [])
    }

    // MARK: Hover documentation

    /// Builds this window's hover documentation: a doc-comment index shared by every pane, tiered behind
    /// `lspRegistry` for on-disk Swift files on the new side. It indexes only while the setting shows hover
    /// documentation, and indexes the comparison on screen when the setting turns it on.
    package func attachHoverDocs(lspRegistry: SourceKitLSPRegistry?) {
        let hoverDocs = HoverDocumentationModel(lspRegistry: lspRegistry, taskProvider: taskProvider)
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

    /// Feeds ``hoverDocs`` both sides of every file prepared so far behind the render target, and the right side's
    /// on-disk root when there is one; nothing while hover documentation is off.
    func updateHoverDocs() {
        guard let hoverDocs, hoverDocs.isEnabled else { return }
        let allPairs = pipeline.target?.pairs ?? []
        let prepared = pipeline.prepared
        // Feed the prefix that landed: waiting for every card would starve the index until the last one lands.
        let pairs = allPairs.prefix(prepared.count)
        guard !pairs.isEmpty else { return }
        let root: URL? = if case .directory(let rightRoot) = right.source { rightRoot } else { nil }
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
        let right = diagnostics?.findingsByFile[counterpartPath(of: leftPath, in: .left)] ?? []
        let left = diagnostics?.leftFindingsByFile[leftPath] ?? []
        return DiagnosticSeverityCounts(right + left)
    }

    /// Tells ``diagnostics`` what each side of the comparison offers the analyzers (DIAG-08, D12).
    func updateDiagnostics() {
        updateAnalyzedSides()
    }
}

import AemiCore
package import AtelierDiagnostics
package import AtelierLSP
import Darwin
import DiffCore
import DiffGit
import DiffRendering
import Foundation

/// Whether the calling thread is the main thread, for asserting that work runs off it.
private func isOnMainThread() -> Bool {
    pthread_main_np() != 0
}

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
    /// `lspRegistry` for on-disk Swift files on the new side.
    package func attachHoverDocs(lspRegistry: SourceKitLSPRegistry?) {
        hoverDocs = HoverDocumentationModel(lspRegistry: lspRegistry, taskProvider: taskProvider)
    }

    /// Feeds ``hoverDocs`` both sides of every file prepared so far behind the render target, and the right side's
    /// on-disk root when there is one.
    func updateHoverDocs() {
        guard let hoverDocs else { return }
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

    /// The severity counts of the file at `leftPath`, whose findings are keyed by its right path.
    package func diagnosticSeverityCounts(for leftPath: String) -> DiagnosticSeverityCounts {
        DiagnosticSeverityCounts(diagnostics?.findingsByFile[counterpartPath(of: leftPath, in: .left)] ?? [])
    }

    /// Tells ``diagnostics`` the right side's changed Swift files and a changeset fingerprint; a right side that is
    /// not a directory reports no root, which clears the findings.
    func updateDiagnostics() {
        diagnosticsTask?.cancel()
        diagnosticsGeneration += 1
        guard let diagnostics else { return }
        guard case .directory(let rightRoot) = right.source else {
            diagnostics.comparisonChanged(root: nil, files: [], corpusFingerprint: nil)
            return
        }
        let changedPaths = comparison.changedPaths(under: nil, limit: Self.combinedFileLimit)
        let swiftFiles: [DiagnosticsEngine.FileTarget] = changedPaths.filter { $0.hasSuffix(".swift") }
            .compactMap { leftPath in
                let rightPath = comparison.counterpartPath(of: leftPath, in: .left)
                guard let entry = right.entriesByPath[rightPath] else { return nil }
                // A file too large to hash falls back to its size, enough to notice a length change.
                let contentHash = entry.blobID ?? "size:\(entry.size)"
                return DiagnosticsEngine.FileTarget(
                    path: rightPath, contentHash: contentHash, url: rightRoot.appending(path: rightPath))
            }
        let leftEntries = left.entriesByPath
        let rightEntries = right.entriesByPath
        let comparison = comparison
        let generation = diagnosticsGeneration
        diagnosticsTask = taskProvider.task {
            let corpusFingerprint = await Self.corpusFingerprint(
                changedPaths: changedPaths, comparison: comparison, leftEntries: leftEntries,
                rightEntries: rightEntries)
            guard generation == diagnosticsGeneration else { return }
            diagnostics.comparisonChanged(root: rightRoot, files: swiftFiles, corpusFingerprint: corpusFingerprint)
        }
    }

    /// A hash of every changed path with its content hash, in sorted order, computed off the main actor.
    @concurrent
    private static func corpusFingerprint(
        changedPaths: [String], comparison: Comparison, leftEntries: [String: SourceEntry],
        rightEntries: [String: SourceEntry]
    ) async -> String {
        assert(!isOnMainThread(), "corpusFingerprint must run off the main actor")
        let fingerprintEntries = changedPaths.sorted()
            .map { leftPath -> String in
                let rightPath = comparison.counterpartPath(of: leftPath, in: .left)
                let hash = rightEntries[rightPath]?.blobID ?? leftEntries[leftPath]?.blobID ?? "-"
                return "\(rightPath)=\(hash)"
            }
        return SourceLoader.blobID(of: Data(fingerprintEntries.joined(separator: "\n").utf8))
    }
}

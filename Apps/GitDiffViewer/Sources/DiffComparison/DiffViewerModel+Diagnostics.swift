import AemiCore
package import AtelierDiagnostics
package import AtelierLSP
import Darwin
import DiffCore
import DiffGit
import DiffRendering
import Foundation

/// Whether the calling thread is the process' main thread; used to assert the executor contract of
/// ``DiffViewerModel/corpusFingerprint(changedPaths:comparison:leftEntries:rightEntries:)`` stays off it, in
/// debug builds and under tests.
private func isOnMainThread() -> Bool {
    pthread_main_np() != 0
}

/// Diagnostics and hover documentation wiring for ``DiffViewerModel``, split out of the main file to keep it under
/// the `file_length` limit. `pipeline`, `taskProvider` and `diagnosticsVersion`'s setter are widened from `private`
/// to `internal` on the main type so this extension can reach them; everything else it touches was already
/// `package`.
extension DiffViewerModel {
    // MARK: Diagnostics

    /// Builds and wires this window's diagnostics: a session over `engine` sharing this model's own task provider,
    /// and a model bridging it to `settings`. Safe to call for every comparison window, a patch's included: a
    /// comparison with no working-tree root simply reports nothing to the engine, so diagnostics stay idle.
    package func attachDiagnostics(engine: DiagnosticsEngine, settings: ViewerSettings) {
        let session = DiagnosticsSession(engine: engine, taskProvider: RuntimeTaskProviderBridge(taskProvider))
        let diagnosticsModel = DiagnosticsModel(session: session, settings: settings)
        diagnosticsModel.onFindingsChanged = { [weak self] _ in self?.diagnosticsVersion &+= 1 }
        diagnostics = diagnosticsModel
    }

    /// Maps each rendered row's `fileIndex` to the path its findings are keyed under, from the pairs behind the
    /// current render target.
    package var diagnosticFilePaths: [Int: String] {
        DiagnosticFileIndex.paths(for: pipeline.target?.pairs ?? [])
    }

    // MARK: Hover documentation

    /// Builds and wires this window's hover documentation: a doc-comment index shared by every pane, tiered
    /// behind `lspRegistry` for on-disk Swift files on the new side. Safe to call for every comparison window;
    /// a comparison with no on-disk right side simply never has a language server to try.
    package func attachHoverDocs(lspRegistry: SourceKitLSPRegistry?) {
        hoverDocs = HoverDocumentationModel(lspRegistry: lspRegistry, taskProvider: taskProvider)
    }

    /// Feeds ``hoverDocs`` both sides of every file currently prepared behind the render target, and the right
    /// side's on-disk root when there is one. Called whenever the pipeline publishes, so hover keeps up with
    /// whatever has actually been diffed, streaming in as more cards of a combined view finish preparing.
    func updateHoverDocs() {
        guard let hoverDocs else { return }
        let pairs = pipeline.target?.pairs ?? []
        let prepared = pipeline.prepared
        guard pairs.count == prepared.count else { return }
        let root: URL? = if case .directory(let rightRoot) = right.source { rightRoot } else { nil }
        let files = zip(pairs.indices, zip(pairs, prepared))
            .map { index, pair in
                let (filePair, diff) = pair
                return HoverDocumentationModel.FileEntry(
                    index: index, leftPath: filePair.path, rightPath: filePair.new?.relativePath,
                    oldText: diff.model.oldText, newText: diff.model.newText, oldBlobID: filePair.old?.blobID,
                    newBlobID: filePair.new?.blobID)
            }
        hoverDocs.comparisonChanged(root: root, files: files)
    }

    /// This file's diagnostics, by its own left path: looked up under the right path ``findingsByFile`` keys them
    /// with, since that is the side diagnostics actually scanned.
    package func diagnosticSeverityCounts(for leftPath: String) -> DiagnosticSeverityCounts {
        DiagnosticSeverityCounts(diagnostics?.findingsByFile[counterpartPath(of: leftPath, in: .left)] ?? [])
    }

    /// Tells ``diagnostics`` what changed: the right side's changed Swift files, on disk when the right side is a
    /// working tree, plus a fingerprint of the whole changeset for corpus-scoped tools. Diagnostics only make
    /// sense against a working tree the tools can actually run over, so anything else (two arbitrary refs, a
    /// patch) reports no root and clears whatever was showing.
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
                // A file too large to have been hashed during the scan (see `SourceLoader.maximumHashedSize`)
                // falls back to its size: rare, and still enough to notice a length change between runs.
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

    /// The sorted (path, content hash) fingerprint of every changed file, hashed off the main actor (SE-0461's
    /// `@concurrent`): cheap for a handful of files, but a large changeset is enough sorting and hashing to be
    /// worth keeping off the window's own actor. A precise fingerprint would read HEAD's commit and
    /// `git status --porcelain`, but nothing downstream of `Comparison` exposes a `GitClient` to do that with;
    /// this list already changes exactly when the working tree does, which is the property a corpus-scoped
    /// tool's cache key needs.
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

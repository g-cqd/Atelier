import AemiCore
import AtelierDiagnostics
import Darwin
package import DiffGit
import Foundation

/// Whether the calling thread is the main thread, for asserting that work runs off it.
private func isOnMainThread() -> Bool {
    pthread_main_np() != 0
}

/// What each side of the comparison offers the analyzers (DIAG-08, decision D12).
extension DiffViewerModel {
    /// Lets ``diagnostics`` analyze a side that is a git ref: `runner` exports its tree through `GitClient`, and
    /// `trust` admits only the repositories the user trusts. Call once ``attachDiagnostics(engine:settings:)`` has
    /// attached the model.
    package func attachSideAnalysis(trust: RepositoryTrust, runner: any ProcessRunner) {
        diagnostics?.trust = trust
        diagnostics?.treeExporter = GitTreeExporter(runner: runner)
    }

    /// Tells ``diagnostics`` what each side offers: where its content lives and its changed Swift files, by its own
    /// paths, with a fingerprint of the changeset computed off the main actor. A side the analyzers cannot read, a
    /// file or a patch, offers nothing; which sides run is the model's call, from the settings and the user's trust.
    package func updateAnalyzedSides() {
        diagnosticsTask?.cancel()
        diagnosticsGeneration += 1
        guard let diagnostics else { return }
        let changedPaths = comparison.changedPaths(under: nil, limit: Self.combinedFileLimit)
        let comparison = comparison
        let leftEntries = left.entriesByPath
        let rightEntries = right.entriesByPath
        let leftContent = left.source.flatMap(Self.diagnosticsContent)
        let rightContent = right.source.flatMap(Self.diagnosticsContent)
        let generation = diagnosticsGeneration
        diagnosticsTask = taskProvider.task {
            let sides = await Self.diagnosticsSides(
                changedPaths: changedPaths, comparison: comparison, left: (leftContent, leftEntries),
                right: (rightContent, rightEntries))
            guard generation == diagnosticsGeneration else { return }
            diagnostics.comparisonChanged(sides)
        }
    }

    /// Maps each rendered row's `fileIndex` to the left-side path its left-side findings are keyed under, from the
    /// pairs behind the current render target; a file the left side lacks has none.
    package var diagnosticLeftFilePaths: [Int: String] { diagnosticFilePathMaps.left }

    /// Where a source's content lives for the analyzers; nil for a file or a patch, which they cannot read.
    private static func diagnosticsContent(_ source: ComparisonSource) -> DiagnosticsSideTarget.Content? {
        switch source {
            case .directory(let root): .directory(root)
            case .gitRef(let repository, let ref): .ref(repository: repository, ref: ref)
            case .file, .patch: nil
        }
    }

    /// Both sides' targets: each side's changed Swift files by its own paths, with their content hashes, and one
    /// fingerprint of the changeset, computed off the main actor.
    @concurrent
    private static func diagnosticsSides(
        changedPaths: [String], comparison: Comparison,
        left: (content: DiagnosticsSideTarget.Content?, entries: [String: SourceEntry]),
        right: (content: DiagnosticsSideTarget.Content?, entries: [String: SourceEntry])
    ) async -> DiagnosticsSides {
        assert(!isOnMainThread(), "diagnosticsSides must run off the main actor")
        let rightPaths = changedPaths.map { comparison.counterpartPath(of: $0, in: .left) }
        let fingerprint = changesetFingerprint(
            leftPaths: changedPaths, rightPaths: rightPaths, leftEntries: left.entries, rightEntries: right.entries)
        return DiagnosticsSides(
            left: left.content.map {
                target($0, paths: changedPaths, entries: left.entries, fingerprint: fingerprint)
            },
            right: right.content.map {
                target($0, paths: rightPaths, entries: right.entries, fingerprint: fingerprint)
            })
    }

    /// One side's target over the changed `paths` it holds that are Swift sources.
    nonisolated private static func target(
        _ content: DiagnosticsSideTarget.Content, paths: [String], entries: [String: SourceEntry], fingerprint: String
    ) -> DiagnosticsSideTarget {
        let root: URL? = if case .directory(let root) = content { root } else { nil }
        let files = paths.filter { $0.hasSuffix(".swift") }
            .compactMap { path -> DiagnosticsEngine.FileTarget? in
                guard let entry = entries[path] else { return nil }
                // A file too large to hash falls back to its size, enough to notice a length change.
                return DiagnosticsEngine.FileTarget(
                    path: path, contentHash: entry.blobID ?? "size:\(entry.size)", url: root?.appending(path: path))
            }
        return DiagnosticsSideTarget(content: content, files: files, corpusFingerprint: fingerprint)
    }

    /// A hash of every changed path with both sides' content hashes, in a stable order: a change on either side,
    /// a configuration file included, makes another fingerprint.
    nonisolated private static func changesetFingerprint(
        leftPaths: [String], rightPaths: [String], leftEntries: [String: SourceEntry],
        rightEntries: [String: SourceEntry]
    ) -> String {
        let lines = zip(leftPaths, rightPaths)
            .map { leftPath, rightPath in
                let leftHash = leftEntries[leftPath]?.blobID ?? "-"
                let rightHash = rightEntries[rightPath]?.blobID ?? "-"
                return "\(leftPath)=\(leftHash)\t\(rightPath)=\(rightHash)"
            }
            .sorted()
        return SourceLoader.blobID(of: Data(lines.joined(separator: "\n").utf8))
    }
}

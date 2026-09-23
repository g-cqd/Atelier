package import AtelierDiagnostics
package import DiffGit
package import Foundation

/// A side of a comparison, as the analyzers see it.
package enum DiagnosticsSide: Hashable, Sendable, CaseIterable {
    /// The left, older side.
    case left
    /// The right, newer side.
    case right
}

/// What one side of a comparison offers the analyzers: where its content lives, and its changed Swift files.
package struct DiagnosticsSideTarget: Equatable, Sendable {
    /// Where a side's content lives.
    package enum Content: Equatable, Sendable {
        /// A folder analyzed in place, such as the working tree.
        case directory(URL)
        /// A branch, tag or commit of a repository, exported into a private folder for its analysis.
        case ref(repository: URL, ref: String)
    }

    package var content: Content
    /// The side's changed Swift files, by the side's own root-relative paths.
    package var files: [DiagnosticsEngine.FileTarget]
    /// Identifies the changeset for the tools that read the whole corpus; a ref side is keyed by its tree instead.
    package var corpusFingerprint: String?

    package init(content: Content, files: [DiagnosticsEngine.FileTarget], corpusFingerprint: String?) {
        self.content = content
        self.files = files
        self.corpusFingerprint = corpusFingerprint
    }

    /// The folder or repository the side reads from, which tells one comparison's findings from another's.
    var location: URL {
        switch content {
            case .directory(let root): root
            case .ref(let repository, _): repository
        }
    }
}

/// What each side of a comparison offers the analyzers; nil for a side they cannot read, such as a patch.
package struct DiagnosticsSides: Equatable, Sendable {
    package var left: DiagnosticsSideTarget?
    package var right: DiagnosticsSideTarget?

    package init(left: DiagnosticsSideTarget? = nil, right: DiagnosticsSideTarget? = nil) {
        self.left = left
        self.right = right
    }

    package subscript(side: DiagnosticsSide) -> DiagnosticsSideTarget? {
        switch side {
            case .left: left
            case .right: right
        }
    }
}

/// What one diagnostics run analyzes: the sides ``AnalyzedSides`` includes that have changed Swift files (DIAG-01) and
/// can be read, the right side first, with the tools enabled. A side that is a git ref needs an exporter and a
/// repository the user trusts; without both only a folder, such as the working tree, is analyzed (decision D12).
struct DiagnosticsPlan: Equatable {
    struct SideRun: Equatable {
        let side: DiagnosticsSide
        let target: DiagnosticsSideTarget
    }

    let runs: [SideRun]
    let tools: [DiagnosticTool: ToolLocation]

    init(
        sides: DiagnosticsSides, mode: AnalyzedSides, tools: [DiagnosticTool: ToolLocation], canExport: Bool,
        isTrusted: (URL) -> Bool
    ) {
        self.tools = tools
        runs = [DiagnosticsSide.right, .left]
            .compactMap { side in
                guard side == .right ? mode.includesRight : mode.includesLeft, let target = sides[side],
                    !target.files.isEmpty
                else { return nil }
                if case .ref(let repository, _) = target.content, !canExport || !isTrusted(repository) { return nil }
                return SideRun(side: side, target: target)
            }
    }

    /// Whether the run has nothing to do.
    var isEmpty: Bool { runs.isEmpty || tools.isEmpty }

    /// The folders and repositories the plan reads from.
    var locations: Set<URL> { Set(runs.map(\.target.location)) }
}

/// Puts a ref side's content on disk for its analysis.
package protocol DiagnosticsTreeExporting: Sendable {
    /// The tree `ref` names in `repository`, which keys the side's cached results.
    func treeID(of ref: String, in repository: URL) async throws -> String

    /// Puts the files the tools read of `tree`, in `repository`, into a private folder for as long as the
    /// materializer's body runs.
    func materializer(for tree: String, in repository: URL) -> DiagnosticsMaterializer
}

/// Exports through ``GitClient``: `git archive` of the tree into a private temporary folder, under the repository's
/// configuration gate and the isolation flags, with nothing a repository could choose run along the way.
package struct GitTreeExporter: DiagnosticsTreeExporting {
    private let runner: any ProcessRunner

    /// - Parameter runner: How git is spawned: the app's git runner, which quitting interrupts.
    package init(runner: any ProcessRunner) {
        self.runner = runner
    }

    package func treeID(of ref: String, in repository: URL) async throws -> String {
        try await GitClient(repository: repository, runner: runner).treeID(of: ref)
    }

    package func materializer(for tree: String, in repository: URL) -> DiagnosticsMaterializer {
        let client = GitClient(repository: repository, runner: runner)
        return { body in
            try await client.withExportedTree(tree, including: DiagnosticTool.readsFile(at:)) { folder in
                try await body(folder)
            }
        }
    }
}

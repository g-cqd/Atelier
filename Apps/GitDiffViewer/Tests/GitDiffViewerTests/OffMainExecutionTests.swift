import AemiCore
import AemiTesting
import AtelierDiagnostics
import AtelierFileTree
import Darwin
import DiffCore
import DiffGit
import Foundation
import Testing

@testable import DiffComparison
@testable import DiffRendering
@testable import DiffTextKit

/// Whether the calling thread is the process' main thread; a private copy of the same probe the production
/// `@concurrent` seams assert with, so these tests can observe the same executor contract from the outside.
private func isOnMainThread() -> Bool {
    pthread_main_np() != 0
}

/// Proves the `@concurrent` seams this offload wave introduced actually run off the main actor when called from
/// it, and that they still answer exactly what their synchronous counterpart would (SE-0461 changes only where
/// work runs, never what it computes).
@MainActor
struct OffMainExecutionTests {
    /// A minimal companion seam with no production purpose beyond this test: proves `@concurrent` itself
    /// guarantees the global executor under this package's settings, independent of any one wrapper's own logic.
    @concurrent
    private static func probeIsOnMain() async -> Bool {
        isOnMainThread()
    }

    @Test
    func `a bare @concurrent function called from the main actor runs off it`() async {
        #expect(isOnMainThread())
        let ranOnMain = await Self.probeIsOnMain()
        #expect(!ranOnMain)
    }

    // MARK: DiagnosticRowMapper

    private func finding(line: Int, file: String = "a.swift") -> Finding {
        Finding(
            tool: .swiftlint, ruleID: "rule", message: "message", file: file, line: line, column: nil,
            endLine: nil, endColumn: nil, severity: .warning)
    }

    @Test
    func `rowsOffMain runs off the main actor and answers the same mapping as rows`() async throws {
        let text = "line1\nline2\nline3\n"
        let rendered = try #require(DiffRenderer.render(oldText: text, newText: text, language: .plain).new)
        let paths = [0: "a.swift"]
        let findings = ["a.swift": [finding(line: 2)]]

        #expect(isOnMainThread())
        let rows = await DiagnosticRowMapper.rowsOffMain(for: rendered, paths: paths, findings: findings)
        let syncRows = DiagnosticRowMapper.rows(for: rendered, paths: paths, findings: findings)

        #expect(rows.keys == syncRows.keys)
        #expect(rows[1]?.severity == syncRows[1]?.severity)
        #expect(rows[1]?.findings == syncRows[1]?.findings)
    }

    // MARK: ExplorerTrees

    private func entry(_ path: String, _ blob: String) -> SourceEntry {
        SourceEntry(relativePath: path, blobID: blob, size: 1)
    }

    @Test
    func `buildOffMain runs off the main actor and answers the same trees as build`() async {
        let comparison = Comparison(
            left: [entry("a/x.swift", "1"), entry("z.swift", "2")],
            right: [entry("a/x.swift", "9"), entry("z.swift", "2")], leftSource: nil, rightSource: nil,
            leftIgnored: [], rightIgnored: [])
        let leftTree = PathNode.tree(from: ["a/x.swift", "z.swift"])
        let rightTree = PathNode.tree(from: ["a/x.swift", "z.swift"])

        #expect(isOnMainThread())
        let built = await ExplorerTrees.buildOffMain(
            comparison: comparison, leftTree: leftTree, rightTree: rightTree, showsChangesOnly: false,
            style: .hierarchy)
        let sync = ExplorerTrees.build(
            comparison: comparison, leftTree: leftTree, rightTree: rightTree, showsChangesOnly: false,
            style: .hierarchy)

        #expect(built.left.map(\.id) == sync.left.map(\.id))
        #expect(built.statuses == sync.statuses)
    }

    // MARK: DiffViewerModel staleness

    @Test
    func `two rapid rebuilds apply only the latest trees`() async throws {
        let harness = ModelTestHarness()
        let sut = harness.makeSUT()
        harness.reader.entries[.directory(ModelTestHarness.leftURL)] = [
            harness.entry("a.swift", "1"), harness.entry("b.swift", "2")
        ]
        harness.reader.entries[.directory(ModelTestHarness.rightURL)] = [
            harness.entry("a.swift", "9"), harness.entry("b.swift", "2")
        ]
        try await harness.load(sut)

        sut.rebuildTrees()
        sut.rebuildTrees()
        try await harness.taskProvider.waitForAllTasks()

        #expect(sut.leftTree.map(\.id) == ["a.swift", "b.swift"])
    }
}

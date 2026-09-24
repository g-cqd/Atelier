import AemiCore
import AemiTesting
import AtelierDiagnostics
import AtelierFileTree
import Darwin
import DiffCore
import DiffGit
import Foundation
import Synchronization
import Testing

@testable import DiffComparison
@testable import DiffRendering
@testable import DiffTextKit

/// Whether the calling thread is the main thread.
private func isOnMainThread() -> Bool {
    pthread_main_np() != 0
}

/// The `@concurrent` seams run off the main actor when called from it, and answer what their synchronous
/// counterparts do.
@MainActor
struct OffMainExecutionTests {
    /// A bare `@concurrent` function, proving the attribute alone leaves the main actor under this package's settings.
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
        let right = SideFindings(paths: paths, findings: findings)
        let rows = await DiagnosticRowMapper.rowsOffMain(for: rendered, left: .none, right: right)
        let syncRows = DiagnosticRowMapper.rows(for: rendered, left: .none, right: right)

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

    // MARK: Repository prologue

    @Test
    func `loadSides lists and indexes both sides off the main actor`() async throws {
        let root = URL(filePath: "/prologue", directoryHint: .isDirectory)
        let reader = FakeSourceReader()
        reader.repositories[root] = RepositoryInfo(root: root, branches: ["main"], tags: [], commits: [])
        reader.entries[.gitRef(repository: root, ref: "HEAD")] = [entry("a/one.swift", "1")]
        reader.entries[.gitRef(repository: root, ref: "main")] = [entry("b/two.swift", "2")]
        let ranOnMain = Mutex<[Bool]>([])

        #expect(isOnMainThread())
        let loaded = try #require(
            await DiffViewerModel.loadSides(
                in: root, leftRef: "HEAD", rightRef: "main", reader: reader,
                threadProbe: { ranOnMain.withLock { $0.append(isOnMainThread()) } }))

        // Once as the prologue starts, then once per side as its index is built.
        #expect(ranOnMain.withLock { $0 } == [false, false, false])
        #expect(loaded.leftListing?.entriesByPath["a/one.swift"]?.blobID == "1")
        #expect(loaded.leftListing?.tree.map(\.id) == ["a"])
        #expect(loaded.rightListing?.entriesByPath["b/two.swift"]?.blobID == "2")
        #expect(loaded.rightListing?.tree.map(\.id) == ["b"])
    }

    @Test
    func `a prepared side index keeps the first entry listed for a path`() {
        let listing = SideState.Listing(
            entries: [entry("a/one.swift", "first"), entry("a/one.swift", "second")], commit: nil)

        #expect(listing.entriesByPath["a/one.swift"]?.blobID == "first")
        #expect(listing.tree.map(\.id) == ["a"])
    }
}

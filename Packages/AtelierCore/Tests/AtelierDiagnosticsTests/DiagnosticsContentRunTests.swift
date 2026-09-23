import AemiTestKit
import AtelierProcess
import AtelierTestSupport
import Foundation
import Synchronization
import Testing

@testable import AtelierDiagnostics

/// Analyzing content that is not on disk until the caller puts it there, such as a git ref exported into a throwaway
/// folder: the engine's cache keyed by content, and the session run that exports only when a tool must run.
struct DiagnosticsContentRunTests {
    // MARK: - The engine's cache by content

    private static func contentRequest(root: URL, identity: String, tool: DiagnosticTool, executable: URL)
        -> DiagnosticsEngine.Request
    {
        DiagnosticsEngine.Request(
            root: root, files: [.init(path: "A.swift", contentHash: "a", url: root.appending(path: "A.swift"))],
            corpusFingerprint: identity, tools: [tool: ToolLocation(customPath: executable.path)],
            contentIdentity: identity)
    }

    @Test
    func `the same tree in another folder is answered from the cache without running the tool`() async throws {
        let temp = TemporaryDirectory(prefix: "diagcontent")
        defer { temp.cleanup() }
        let first = URL(filePath: temp.file("export-1"))
        let second = URL(filePath: temp.file("export-2"))
        let executable = URL(filePath: temp.file("tool/swiftlint"))
        try DiagnosticsEngineTests.makeExecutable(at: executable)
        let runner = FakeProcessRunner(always: DiagnosticsEngineTests.sarifOutput(root: first))
        let engine = DiagnosticsEngine(
            runner: runner,
            discovery: DiagnosticsEngineTests.discovery(
                runner: runner, executable: executable, home: URL(filePath: temp.file("home"))))
        let ran = try await engine.run(
            .swiftlint,
            request: Self.contentRequest(root: first, identity: "tree-1", tool: .swiftlint, executable: executable))

        let again = try await engine.run(
            .swiftlint,
            request: Self.contentRequest(root: second, identity: "tree-1", tool: .swiftlint, executable: executable))

        #expect(again.fromCache)
        #expect(again.findings == ran.findings)
        #expect(runner.specs.count == 1)
    }

    @Test
    func `a cached tree is known before its files exist again`() async throws {
        let temp = TemporaryDirectory(prefix: "diagcontent")
        defer { temp.cleanup() }
        let export = URL(filePath: temp.file("export"))
        let executable = URL(filePath: temp.file("tool/swiftlint"))
        try DiagnosticsEngineTests.makeExecutable(at: executable)
        let runner = FakeProcessRunner(always: DiagnosticsEngineTests.sarifOutput(root: export))
        let engine = DiagnosticsEngine(
            runner: runner,
            discovery: DiagnosticsEngineTests.discovery(
                runner: runner, executable: executable, home: URL(filePath: temp.file("home"))))
        let ran = try await engine.run(
            .swiftlint,
            request: Self.contentRequest(root: export, identity: "tree-1", tool: .swiftlint, executable: executable))

        let known = await engine.cachedResult(
            .swiftlint,
            request: Self.contentRequest(
                root: URL(filePath: temp.file("not-exported-yet")), identity: "tree-1", tool: .swiftlint,
                executable: executable))

        #expect(known?.fromCache == true)
        #expect(known?.findings == ran.findings)
    }

    @Test
    func `another tree is not known until it runs`() async throws {
        let temp = TemporaryDirectory(prefix: "diagcontent")
        defer { temp.cleanup() }
        let export = URL(filePath: temp.file("export"))
        let executable = URL(filePath: temp.file("tool/swiftlint"))
        try DiagnosticsEngineTests.makeExecutable(at: executable)
        let runner = FakeProcessRunner(always: DiagnosticsEngineTests.sarifOutput(root: export))
        let engine = DiagnosticsEngine(
            runner: runner,
            discovery: DiagnosticsEngineTests.discovery(
                runner: runner, executable: executable, home: URL(filePath: temp.file("home"))))
        _ = try await engine.run(
            .swiftlint,
            request: Self.contentRequest(root: export, identity: "tree-1", tool: .swiftlint, executable: executable))

        let known = await engine.cachedResult(
            .swiftlint,
            request: Self.contentRequest(root: export, identity: "tree-2", tool: .swiftlint, executable: executable))

        #expect(known == nil)
    }

    @Test
    func `a tree without the configuration its tool needs is known to skip without its files`() async throws {
        let temp = TemporaryDirectory(prefix: "diagcontent")
        defer { temp.cleanup() }
        let export = URL(filePath: temp.file("export"))
        try FileManager.default.createDirectory(at: export, withIntermediateDirectories: true)
        let executable = URL(filePath: temp.file("tool/swift-format"))
        try DiagnosticsEngineTests.makeExecutable(at: executable)
        let runner = FakeProcessRunner(always: .success(""))
        let engine = DiagnosticsEngine(
            runner: runner,
            discovery: DiagnosticsEngineTests.discovery(
                runner: runner, executable: executable, home: URL(filePath: temp.file("home"))))
        _ = try await engine.run(
            .swiftFormat,
            request: Self.contentRequest(root: export, identity: "tree-1", tool: .swiftFormat, executable: executable))

        let known = await engine.cachedResult(
            .swiftFormat,
            request: Self.contentRequest(
                root: URL(filePath: temp.file("gone")), identity: "tree-1", tool: .swiftFormat, executable: executable))

        guard case .skipped = known?.status else {
            Issue.record("expected a cached skip, got \(String(describing: known?.status))")
            return
        }
        #expect(runner.specs.isEmpty)
    }

    // MARK: - The session's run on content put on disk

    private static let request = DiagnosticsEngine.Request(
        root: URL(filePath: "/nowhere"), files: [.init(path: "A.swift", contentHash: "a", url: nil)],
        corpusFingerprint: "tree-1", tools: [.swiftlint: ToolLocation(), .arcleak: ToolLocation()],
        contentIdentity: "tree-1")

    @Test
    func `every tool the cache answers reports without the files being put on disk`() async throws {
        let runner = ContentRunner(cached: [.swiftlint, .arcleak])
        let materializations = Materializations()

        let updates = await Self.analyze(Self.request, with: runner, materializations: materializations)

        #expect(Set(updates.map(\.result.tool)) == [.swiftlint, .arcleak])
        #expect(materializations.count == 0)
        #expect(await runner.roots.isEmpty)
    }

    @Test
    func `the tools the cache cannot answer run once against the folder the files were put in`() async throws {
        let runner = ContentRunner(cached: [.swiftlint])
        let materializations = Materializations()

        let updates = await Self.analyze(Self.request, with: runner, materializations: materializations)

        #expect(updates.map(\.result.tool).sorted { $0.rawValue < $1.rawValue } == [.arcleak, .swiftlint])
        #expect(materializations.count == 1)
        #expect(await runner.roots == [Materializations.folder])
        #expect(updates.last?.isLast == true)
    }

    @Test
    func `files that cannot be put on disk fail every tool left, and only those`() async throws {
        let runner = ContentRunner(cached: [.swiftlint])
        let materializations = Materializations(failing: true)

        let updates = await Self.analyze(Self.request, with: runner, materializations: materializations)

        let arcleak = try #require(updates.first { $0.result.tool == .arcleak })
        guard case .failed = arcleak.result.status else {
            Issue.record("expected arcleak to fail, got \(arcleak.result.status)")
            return
        }
        #expect(updates.first { $0.result.tool == .swiftlint }?.result.status == .succeeded)
        #expect(await runner.roots.isEmpty)
    }

    private static func analyze(
        _ request: DiagnosticsEngine.Request, with runner: ContentRunner, materializations: Materializations
    ) async -> [DiagnosticsSession.Update] {
        let updates = Mutex<[DiagnosticsSession.Update]>([])
        await DiagnosticsSession(engine: runner)
            .analyze(request, materializingWith: materializations.materialize) {
                update in updates.withLock { $0.append(update) }
            }
        return updates.withLock { $0 }
    }
}

/// Counts how often the files were put on disk, into ``folder``, or fails to put them there.
private final class Materializations: Sendable {
    static let folder = URL(filePath: "/materialized", directoryHint: .isDirectory)
    private let calls = Mutex(0)
    private let failing: Bool

    init(failing: Bool = false) {
        self.failing = failing
    }

    var count: Int { calls.withLock { $0 } }

    var materialize: DiagnosticsMaterializer {
        { [self] body in
            calls.withLock { $0 += 1 }
            if failing { throw CocoaError(.fileWriteNoPermission) }
            try await body(Self.folder)
        }
    }
}

/// A runner whose cache answers the tools it was given, and that records the root of every run.
private actor ContentRunner: DiagnosticsRunning {
    private let cached: Set<DiagnosticTool>
    private(set) var roots: [URL] = []

    init(cached: Set<DiagnosticTool>) {
        self.cached = cached
    }

    func run(_ tool: DiagnosticTool, request: DiagnosticsEngine.Request) async throws -> DiagnosticsEngine.ToolResult {
        roots.append(request.root)
        return DiagnosticsEngine.ToolResult(
            tool: tool, findings: [], status: .succeeded, duration: .zero, fromCache: false)
    }

    func cachedResult(_ tool: DiagnosticTool, request: DiagnosticsEngine.Request) async -> DiagnosticsEngine.ToolResult?
    {
        guard cached.contains(tool) else { return nil }
        return DiagnosticsEngine.ToolResult(
            tool: tool, findings: [], status: .succeeded, duration: .zero, fromCache: true)
    }
}

import AemiTestKit
import AtelierProcess
import AtelierTestSupport
import Foundation
import Testing

@testable import AtelierDiagnostics

/// ``DiagnosticsEngine``'s cache identity: a per-file tool's key holds the root and the path/hash pairs, so a rename
/// never aliases the old path and two repositories never share a result.
struct DiagnosticsEngineCacheIdentityTests {
    @Test
    func `renaming a file without changing its content busts the cache instead of aliasing the old path`()
        async throws
    {
        let temp = TemporaryDirectory(prefix: "diageng")
        defer { temp.cleanup() }
        let root = URL(filePath: temp.file("root"))
        let executable = URL(filePath: temp.file("tool/arcleak"))
        try DiagnosticsEngineTests.makeExecutable(at: executable)
        let runner = FakeProcessRunner(always: DiagnosticsEngineTests.sarifOutput(root: root))
        let discovery = DiagnosticsEngineTests.discovery(
            runner: runner, executable: executable, home: URL(filePath: temp.file("home")))
        let engine = DiagnosticsEngine(runner: runner, discovery: discovery)

        // The same content under a new path: a key of hashes alone would answer from cache under the old path.
        let first = try await engine.run(
            .arcleak,
            request: DiagnosticsEngineTests.request(
                root: root,
                files: [
                    DiagnosticsEngine.FileTarget(
                        path: "A.swift", contentHash: "hash-1", url: root.appending(path: "A.swift"))
                ],
                tool: .arcleak, customPath: executable.path)
        )
        let second = try await engine.run(
            .arcleak,
            request: DiagnosticsEngineTests.request(
                root: root,
                files: [
                    DiagnosticsEngine.FileTarget(
                        path: "B.swift", contentHash: "hash-1", url: root.appending(path: "B.swift"))
                ],
                tool: .arcleak, customPath: executable.path)
        )

        #expect(!first.fromCache)
        #expect(!second.fromCache)
        #expect(runner.specs.count == 2)
    }

    @Test
    func `two different roots with the same file paths and hashes never share a cached result`() async throws {
        let temp = TemporaryDirectory(prefix: "diageng")
        defer { temp.cleanup() }
        let rootA = URL(filePath: temp.file("rootA"))
        let rootB = URL(filePath: temp.file("rootB"))
        let executable = URL(filePath: temp.file("tool/arcleak"))
        try DiagnosticsEngineTests.makeExecutable(at: executable)
        let runner = FakeProcessRunner(always: DiagnosticsEngineTests.sarifOutput(root: rootA))
        let discovery = DiagnosticsEngineTests.discovery(
            runner: runner, executable: executable, home: URL(filePath: temp.file("home")))
        let engine = DiagnosticsEngine(runner: runner, discovery: discovery)

        let fileA = DiagnosticsEngine.FileTarget(
            path: "A.swift", contentHash: "hash-1", url: rootA.appending(path: "A.swift"))
        let fileB = DiagnosticsEngine.FileTarget(
            path: "A.swift", contentHash: "hash-1", url: rootB.appending(path: "A.swift"))
        let first = try await engine.run(
            .arcleak,
            request: DiagnosticsEngineTests.request(
                root: rootA, files: [fileA], tool: .arcleak, customPath: executable.path))
        let second = try await engine.run(
            .arcleak,
            request: DiagnosticsEngineTests.request(
                root: rootB, files: [fileB], tool: .arcleak, customPath: executable.path))

        #expect(!first.fromCache)
        #expect(!second.fromCache)
        #expect(runner.specs.count == 2)
    }
}

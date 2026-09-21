import AemiTestKit
import AtelierProcess
import AtelierTestSupport
import Darwin
import Foundation
import Synchronization
import Testing

@testable import AtelierDiagnostics

/// Whether the calling thread is the process' main thread; a private copy of the same probe the production
/// `@concurrent` seams assert with, so these tests can observe the same executor contract from the outside.
private func isOnMainThread() -> Bool {
    pthread_main_np() != 0
}

/// Proves the CPU-bound work `DiagnosticsEngine` does per tool-run stays off the main actor: `run(_:request:)`
/// is called from a `@MainActor` test, and the fake runner — invoked from inside `run`, on the same path that
/// leads to the now-`@concurrent` `parsedFindings` — records the thread it executed on.
@MainActor
struct OffMainExecutionTests {
    private static let sarif = """
        {"version": "2.1.0", "runs": [{"results": []}]}
        """

    private static func makeExecutable(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    @Test
    func `a tool run, called from the main actor, executes its runner and parses its output off the main thread`()
        async throws
    {
        let temp = TemporaryDirectory(prefix: "offmain")
        defer { temp.cleanup() }
        let root = URL(filePath: temp.file("root"))
        let executable = URL(filePath: temp.file("tool/swiftlint"))
        try Self.makeExecutable(at: executable)

        let observedOnMain = Mutex(false)
        let sarif = Self.sarif
        let runner = FakeProcessRunner { _ in
            observedOnMain.withLock { $0 = isOnMainThread() }
            return .success(sarif)
        }
        let discovery = ToolDiscovery(
            runner: runner, bundledDirectory: nil, homeDirectory: URL(filePath: temp.file("home")),
            environment: [:])
        let engine = DiagnosticsEngine(runner: runner, discovery: discovery)

        #expect(isOnMainThread())

        let file = DiagnosticsEngine.FileTarget(
            path: "A.swift", contentHash: "hash-1", url: root.appending(path: "A.swift"))
        let request = DiagnosticsEngine.Request(
            root: root, files: [file], tools: [.swiftlint: ToolLocation(customPath: executable.path)])

        let result = try await engine.run(.swiftlint, request: request)

        #expect(result.status == .succeeded)
        #expect(!observedOnMain.withLock { $0 })
    }
}

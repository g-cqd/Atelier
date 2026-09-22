import AemiTestKit
import AtelierProcess
import AtelierTestSupport
import Foundation
import Testing

@testable import AtelierDiagnostics

/// ``DiagnosticsEngine``'s caching, scope handling and result mapping, with tools located through a
/// ``ToolDiscovery`` over a custom path so no real tool is ever spawned.
struct DiagnosticsEngineTests {
    static let sarif = """
        {"version": "2.1.0", "runs": [{"results": [
            {"ruleId": "line_length", "level": "warning", "message": {"text": "Line too long"},
             "locations": [{"physicalLocation": {"artifactLocation": {"uri": "file://ROOT/A.swift"},
                 "region": {"startLine": 1}}}]}
        ]}]}
        """

    /// Writes an executable script at `url`; its contents are irrelevant since a ``FakeProcessRunner`` never
    /// actually spawns it, but discovery still needs a real, executable file on disk to find.
    static func makeExecutable(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    static func sarifOutput(root: URL) -> ProcessOutput {
        .success(Self.sarif.replacingOccurrences(of: "ROOT", with: root.path))
    }

    /// A discovery that resolves `tool` to `executable` through a custom path, with every other rung starved of a
    /// runner call by disabling the toolchain search and leaving `PATH` unconsulted (nothing to find there anyway).
    static func discovery(runner: any ProcessRunner, executable: URL, home: URL) -> ToolDiscovery {
        ToolDiscovery(runner: runner, bundledDirectory: nil, homeDirectory: home, environment: [:])
    }

    static func request(
        root: URL, files: [DiagnosticsEngine.FileTarget], corpusFingerprint: String? = nil,
        tool: DiagnosticTool, customPath: String
    ) -> DiagnosticsEngine.Request {
        DiagnosticsEngine.Request(
            root: root, files: files, corpusFingerprint: corpusFingerprint,
            tools: [tool: ToolLocation(customPath: customPath)]
        )
    }

    @Test
    func `a second run of an unchanged request is answered from cache without invoking the runner`() async throws {
        let temp = TemporaryDirectory(prefix: "diageng")
        defer { temp.cleanup() }
        let root = URL(filePath: temp.file("root"))
        let executable = URL(filePath: temp.file("tool/swiftlint"))
        try Self.makeExecutable(at: executable)
        let runner = FakeProcessRunner(always: Self.sarifOutput(root: root))
        let discovery = Self.discovery(runner: runner, executable: executable, home: URL(filePath: temp.file("home")))
        let engine = DiagnosticsEngine(runner: runner, discovery: discovery)

        let file = DiagnosticsEngine.FileTarget(
            path: "A.swift", contentHash: "hash-1", url: root.appending(path: "A.swift"))
        let request = Self.request(
            root: root, files: [file], corpusFingerprint: "fp-1", tool: .swiftlint, customPath: executable.path)

        let first = try await engine.run(.swiftlint, request: request)
        let second = try await engine.run(.swiftlint, request: request)

        #expect(first.status == .succeeded)
        #expect(!first.fromCache)
        #expect(first.findings.count == 1)
        #expect(second.status == .succeeded)
        #expect(second.fromCache)
        #expect(second.findings == first.findings)
        #expect(runner.specs.count == 1)
    }

    @Test
    func `a changed content hash busts the cache`() async throws {
        // arcleak, not swiftlint: swiftlint is corpus-scoped, and its cache payload keys off the corpus
        // fingerprint rather than any one file's content hash.
        let temp = TemporaryDirectory(prefix: "diageng")
        defer { temp.cleanup() }
        let root = URL(filePath: temp.file("root"))
        let executable = URL(filePath: temp.file("tool/arcleak"))
        try Self.makeExecutable(at: executable)
        let runner = FakeProcessRunner(always: Self.sarifOutput(root: root))
        let discovery = Self.discovery(runner: runner, executable: executable, home: URL(filePath: temp.file("home")))
        let engine = DiagnosticsEngine(runner: runner, discovery: discovery)

        let url = root.appending(path: "A.swift")
        let first = try await engine.run(
            .arcleak,
            request: Self.request(
                root: root, files: [DiagnosticsEngine.FileTarget(path: "A.swift", contentHash: "hash-1", url: url)],
                tool: .arcleak, customPath: executable.path)
        )
        let second = try await engine.run(
            .arcleak,
            request: Self.request(
                root: root, files: [DiagnosticsEngine.FileTarget(path: "A.swift", contentHash: "hash-2", url: url)],
                tool: .arcleak, customPath: executable.path)
        )

        #expect(!first.fromCache)
        #expect(!second.fromCache)
        #expect(runner.specs.count == 2)
    }

    @Test
    func `a changed configuration file busts the cache`() async throws {
        let temp = TemporaryDirectory(prefix: "diageng")
        defer { temp.cleanup() }
        let root = URL(filePath: temp.file("root"))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let executable = URL(filePath: temp.file("tool/swiftlint"))
        try Self.makeExecutable(at: executable)
        let runner = FakeProcessRunner(always: Self.sarifOutput(root: root))
        let discovery = Self.discovery(runner: runner, executable: executable, home: URL(filePath: temp.file("home")))
        let engine = DiagnosticsEngine(runner: runner, discovery: discovery)

        let file = DiagnosticsEngine.FileTarget(
            path: "A.swift", contentHash: "hash-1", url: root.appending(path: "A.swift"))
        let request = Self.request(
            root: root, files: [file], corpusFingerprint: "fp-1", tool: .swiftlint, customPath: executable.path)

        let configURL = root.appending(path: ".swiftlint.yml")
        try "one".write(to: configURL, atomically: true, encoding: .utf8)
        let first = try await engine.run(.swiftlint, request: request)

        try "a much longer configuration payload".write(to: configURL, atomically: true, encoding: .utf8)
        let second = try await engine.run(.swiftlint, request: request)

        #expect(!first.fromCache)
        #expect(!second.fromCache)
        #expect(runner.specs.count == 2)
    }

    @Test
    func `a corpus tool caches the full result and re-filters a different file subset without re-running`()
        async throws
    {
        let temp = TemporaryDirectory(prefix: "diageng")
        defer { temp.cleanup() }
        let root = URL(filePath: temp.file("root"))
        let executable = URL(filePath: temp.file("tool/dolly"))
        try Self.makeExecutable(at: executable)
        let sarif = """
            {"version": "2.1.0", "runs": [{"results": [
                {"ruleId": "duplicate", "level": "warning", "message": {"text": "Dup"},
                 "locations": [{"physicalLocation": {"artifactLocation": {"uri": "file://\(root.path)/A.swift"},
                     "region": {"startLine": 1}}}]},
                {"ruleId": "duplicate", "level": "warning", "message": {"text": "Dup"},
                 "locations": [{"physicalLocation": {"artifactLocation": {"uri": "file://\(root.path)/B.swift"},
                     "region": {"startLine": 1}}}]}
            ]}]}
            """
        let runner = FakeProcessRunner(always: .success(sarif))
        let discovery = Self.discovery(runner: runner, executable: executable, home: URL(filePath: temp.file("home")))
        let engine = DiagnosticsEngine(runner: runner, discovery: discovery)

        let both = [
            DiagnosticsEngine.FileTarget(path: "A.swift", contentHash: "a", url: root.appending(path: "A.swift")),
            DiagnosticsEngine.FileTarget(path: "B.swift", contentHash: "b", url: root.appending(path: "B.swift"))
        ]
        let full = try await engine.run(
            .dolly,
            request: Self.request(
                root: root, files: both, corpusFingerprint: "fp-1", tool: .dolly, customPath: executable.path)
        )
        #expect(full.findings.count == 2)
        #expect(!full.fromCache)

        let onlyA = try await engine.run(
            .dolly,
            request: Self.request(
                root: root, files: [both[0]], corpusFingerprint: "fp-1", tool: .dolly, customPath: executable.path)
        )
        #expect(onlyA.fromCache)
        #expect(onlyA.findings.map(\.file) == ["A.swift"])
        #expect(runner.specs.count == 1)
    }

    @Test
    func `a missing tool reports toolMissing`() async throws {
        let temp = TemporaryDirectory(prefix: "diageng")
        defer { temp.cleanup() }
        let root = URL(filePath: temp.file("root"))
        let runner = FakeProcessRunner(always: .success(""))
        let discovery = ToolDiscovery(
            runner: runner, bundledDirectory: nil, homeDirectory: URL(filePath: temp.file("home")),
            environment: [:])
        let engine = DiagnosticsEngine(runner: runner, discovery: discovery)

        let file = DiagnosticsEngine.FileTarget(path: "A.swift", contentHash: "a", url: root.appending(path: "A.swift"))
        // dolly is not a real, installed tool, so no rung of discovery's search finds it.
        let request = DiagnosticsEngine.Request(
            root: root, files: [file], corpusFingerprint: "fp-1", tools: [:])
        let result = try await engine.run(.dolly, request: request)
        #expect(result.status == .toolMissing)
        #expect(result.findings.isEmpty)
    }

    @Test
    func `a nonzero exit code outside the acceptable set is reported as failed`() async throws {
        let temp = TemporaryDirectory(prefix: "diageng")
        defer { temp.cleanup() }
        let root = URL(filePath: temp.file("root"))
        let executable = URL(filePath: temp.file("tool/arcleak"))
        try Self.makeExecutable(at: executable)
        let runner = FakeProcessRunner(always: .failure(2, error: "boom"))
        let discovery = Self.discovery(runner: runner, executable: executable, home: URL(filePath: temp.file("home")))
        let engine = DiagnosticsEngine(runner: runner, discovery: discovery)

        let file = DiagnosticsEngine.FileTarget(path: "A.swift", contentHash: "a", url: root.appending(path: "A.swift"))
        let request = Self.request(root: root, files: [file], tool: .arcleak, customPath: executable.path)
        let result = try await engine.run(.arcleak, request: request)
        guard case .failed(let message) = result.status else {
            Issue.record("expected .failed, got \(result.status)")
            return
        }
        #expect(message == "boom")
    }

    @Test
    func `malformed SARIF is reported as failed`() async throws {
        let temp = TemporaryDirectory(prefix: "diageng")
        defer { temp.cleanup() }
        let root = URL(filePath: temp.file("root"))
        let executable = URL(filePath: temp.file("tool/swiftlint"))
        try Self.makeExecutable(at: executable)
        let runner = FakeProcessRunner(always: .success("not json"))
        let discovery = Self.discovery(runner: runner, executable: executable, home: URL(filePath: temp.file("home")))
        let engine = DiagnosticsEngine(runner: runner, discovery: discovery)

        let file = DiagnosticsEngine.FileTarget(path: "A.swift", contentHash: "a", url: root.appending(path: "A.swift"))
        let request = Self.request(
            root: root, files: [file], corpusFingerprint: "fp-1", tool: .swiftlint, customPath: executable.path)
        let result = try await engine.run(.swiftlint, request: request)
        guard case .failed = result.status else {
            Issue.record("expected .failed, got \(result.status)")
            return
        }
    }

    @Test
    func `a corpus tool without a corpus fingerprint is skipped`() async throws {
        let temp = TemporaryDirectory(prefix: "diageng")
        defer { temp.cleanup() }
        let root = URL(filePath: temp.file("root"))
        let executable = URL(filePath: temp.file("tool/dolly"))
        try Self.makeExecutable(at: executable)
        let runner = FakeProcessRunner(always: .success(""))
        let discovery = Self.discovery(runner: runner, executable: executable, home: URL(filePath: temp.file("home")))
        let engine = DiagnosticsEngine(runner: runner, discovery: discovery)

        let request = Self.request(
            root: root, files: [], corpusFingerprint: nil, tool: .dolly, customPath: executable.path)
        let result = try await engine.run(.dolly, request: request)
        #expect(result.status == .skipped("requires a working tree"))
        #expect(runner.specs.isEmpty)
    }

    @Test
    func `a per-file tool with no files is skipped`() async throws {
        // arcleak, not swiftlint: swiftlint is now corpus-scoped, so an empty file list is not what makes it skip.
        let temp = TemporaryDirectory(prefix: "diageng")
        defer { temp.cleanup() }
        let root = URL(filePath: temp.file("root"))
        let executable = URL(filePath: temp.file("tool/arcleak"))
        try Self.makeExecutable(at: executable)
        let runner = FakeProcessRunner(always: .success(""))
        let discovery = Self.discovery(runner: runner, executable: executable, home: URL(filePath: temp.file("home")))
        let engine = DiagnosticsEngine(runner: runner, discovery: discovery)

        let request = Self.request(root: root, files: [], tool: .arcleak, customPath: executable.path)
        let result = try await engine.run(.arcleak, request: request)
        #expect(result.status == .skipped("no files"))
        #expect(runner.specs.isEmpty)
    }

    @Test
    func `a per-file tool with only blobs not on disk is skipped`() async throws {
        // arcleak, not swiftlint: swiftlint is now corpus-scoped and never reads a file's on-disk URL.
        let temp = TemporaryDirectory(prefix: "diageng")
        defer { temp.cleanup() }
        let root = URL(filePath: temp.file("root"))
        let executable = URL(filePath: temp.file("tool/arcleak"))
        try Self.makeExecutable(at: executable)
        let runner = FakeProcessRunner(always: .success(""))
        let discovery = Self.discovery(runner: runner, executable: executable, home: URL(filePath: temp.file("home")))
        let engine = DiagnosticsEngine(runner: runner, discovery: discovery)

        let file = DiagnosticsEngine.FileTarget(path: "A.swift", contentHash: "a", url: nil)
        let request = Self.request(root: root, files: [file], tool: .arcleak, customPath: executable.path)
        let result = try await engine.run(.arcleak, request: request)
        #expect(result.status == .skipped("sources not on disk"))
        #expect(runner.specs.isEmpty)
    }

    @Test
    func `cancellation propagates as a CancellationError`() async throws {
        let temp = TemporaryDirectory(prefix: "diageng")
        defer { temp.cleanup() }
        let root = URL(filePath: temp.file("root"))
        let executable = URL(filePath: temp.file("tool/swiftlint"))
        try Self.makeExecutable(at: executable)
        let started = AsyncLatch()
        let runner = FakeProcessRunner { _ in
            started.open()
            try Task.checkCancellation()
            while !Task.isCancelled {
                try await Task.sleep(for: .milliseconds(5))
            }
            throw CancellationError()
        }
        let discovery = Self.discovery(runner: runner, executable: executable, home: URL(filePath: temp.file("home")))
        let engine = DiagnosticsEngine(runner: runner, discovery: discovery)

        let file = DiagnosticsEngine.FileTarget(path: "A.swift", contentHash: "a", url: root.appending(path: "A.swift"))
        let request = Self.request(
            root: root, files: [file], corpusFingerprint: "fp-1", tool: .swiftlint, customPath: executable.path)

        let task = Task {
            try await engine.run(.swiftlint, request: request)
        }
        try await started.wait()
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("expected a CancellationError")
        } catch is CancellationError {
            // Expected.
        }
    }
}

import AemiTestKit
import AtelierProcess
import AtelierTestSupport
import Foundation
import Testing

@testable import AtelierDiagnostics

/// ``DiagnosticsEngine`` over a tool that scopes its own report to the request's files: it is given those files, keeps
/// the findings it reports as written, is cached per set of files, and, with none, reports a clean run without
/// launching it.
struct DiagnosticsEngineScopeTests {
    @Test(arguments: [
        (DiagnosticTool.arcleak, ".arcleak.json"), (.dolly, ".dolly.json"), (.deadwood, ".deadwood.json")
    ])
    func `a changed JSON configuration file of an analyzer busts the cache`(tool: DiagnosticTool, configName: String)
        async throws
    {
        let temp = TemporaryDirectory(prefix: "diageng")
        defer { temp.cleanup() }
        let root = URL(filePath: temp.file("root"))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let executable = URL(filePath: temp.file("tool/\(tool.executableName)"))
        try DiagnosticsEngineTests.makeExecutable(at: executable)
        let runner = FakeProcessRunner(always: DiagnosticsEngineTests.sarifOutput(root: root))
        let discovery = DiagnosticsEngineTests.discovery(
            runner: runner, executable: executable, home: URL(filePath: temp.file("home")))
        let engine = DiagnosticsEngine(runner: runner, discovery: discovery)

        let file = DiagnosticsEngine.FileTarget(
            path: "A.swift", contentHash: "hash-1", url: root.appending(path: "A.swift"))
        let request = DiagnosticsEngineTests.request(
            root: root, files: [file], corpusFingerprint: "fp-1", tool: tool, customPath: executable.path)

        let configURL = root.appending(path: configName)
        try "{}".write(to: configURL, atomically: true, encoding: .utf8)
        let first = try await engine.run(tool, request: request)

        try "{\"longer\": true}".write(to: configURL, atomically: true, encoding: .utf8)
        let second = try await engine.run(tool, request: request)

        #expect(!first.fromCache)
        #expect(!second.fromCache)
        #expect(runner.specs.count == 2)
    }

    @Test
    func `a self-scoping tool caches its report per set of files, so a narrower request runs it again`() async throws {
        let temp = TemporaryDirectory(prefix: "diageng")
        defer { temp.cleanup() }
        let root = URL(filePath: temp.file("root"))
        let executable = URL(filePath: temp.file("tool/dolly"))
        try DiagnosticsEngineTests.makeExecutable(at: executable)
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
        let discovery = DiagnosticsEngineTests.discovery(
            runner: runner, executable: executable, home: URL(filePath: temp.file("home")))
        let engine = DiagnosticsEngine(runner: runner, discovery: discovery)

        let both = [
            DiagnosticsEngine.FileTarget(path: "A.swift", contentHash: "a", url: root.appending(path: "A.swift")),
            DiagnosticsEngine.FileTarget(path: "B.swift", contentHash: "b", url: root.appending(path: "B.swift"))
        ]
        let full = try await engine.run(
            .dolly,
            request: DiagnosticsEngineTests.request(
                root: root, files: both, corpusFingerprint: "fp-1", tool: .dolly, customPath: executable.path)
        )
        #expect(full.findings.count == 2)
        #expect(!full.fromCache)

        let onlyA = try await engine.run(
            .dolly,
            request: DiagnosticsEngineTests.request(
                root: root, files: [both[0]], corpusFingerprint: "fp-1", tool: .dolly, customPath: executable.path)
        )
        #expect(!onlyA.fromCache)
        #expect(runner.specs.count == 2)
        let narrower = try #require(runner.specs.last)
        #expect(
            narrower.arguments == [
                "analyze", root.path, "--only-from", "-", "--format", "sarif", "--relative-to", root.path
            ])
        #expect(narrower.standardInput == Data("\(root.appending(path: "A.swift").path)\n".utf8))
    }

    @Test
    func `a self-scoping tool keeps a finding on a file the request does not name, since the tool scoped its report`()
        async throws
    {
        let temp = TemporaryDirectory(prefix: "diageng")
        defer { temp.cleanup() }
        let root = URL(filePath: temp.file("root"))
        let executable = URL(filePath: temp.file("tool/dolly"))
        try DiagnosticsEngineTests.makeExecutable(at: executable)
        // The request names only A.swift; dolly reported a clone group on B.swift, so the tool had already scoped it.
        let sarif = """
            {"version": "2.1.0", "runs": [{"results": [
                {"ruleId": "duplicate", "level": "warning", "message": {"text": "Dup"},
                 "locations": [{"physicalLocation": {"artifactLocation": {"uri": "file://\(root.path)/B.swift"},
                     "region": {"startLine": 1}}}]}
            ]}]}
            """
        let runner = FakeProcessRunner(always: .success(sarif))
        let discovery = DiagnosticsEngineTests.discovery(
            runner: runner, executable: executable, home: URL(filePath: temp.file("home")))
        let engine = DiagnosticsEngine(runner: runner, discovery: discovery)

        let file = DiagnosticsEngine.FileTarget(path: "A.swift", contentHash: "a", url: root.appending(path: "A.swift"))
        let result = try await engine.run(
            .dolly,
            request: DiagnosticsEngineTests.request(
                root: root, files: [file], corpusFingerprint: "fp-1", tool: .dolly, customPath: executable.path)
        )

        #expect(result.status == .succeeded)
        #expect(result.findings.map(\.file) == ["B.swift"])
    }

    @Test(arguments: [DiagnosticTool.arcleak, .dolly, .deadwood])
    func `a tool that scopes its own report with no files reports a clean run without being launched`(
        tool: DiagnosticTool
    ) async throws {
        let temp = TemporaryDirectory(prefix: "diageng")
        defer { temp.cleanup() }
        let root = URL(filePath: temp.file("root"))
        let executable = URL(filePath: temp.file("tool/\(tool.executableName)"))
        try DiagnosticsEngineTests.makeExecutable(at: executable)
        let runner = FakeProcessRunner(always: .success(""))
        let discovery = DiagnosticsEngineTests.discovery(
            runner: runner, executable: executable, home: URL(filePath: temp.file("home")))
        let engine = DiagnosticsEngine(runner: runner, discovery: discovery)

        // A corpus is present, so only the empty file list keeps the tool from launching.
        let request = DiagnosticsEngineTests.request(
            root: root, files: [], corpusFingerprint: "fp-1", tool: tool, customPath: executable.path)
        let result = try await engine.run(tool, request: request)
        #expect(result.status == .succeeded)
        #expect(result.findings.isEmpty)
        #expect(result.fromCache == false)
        #expect(runner.specs.isEmpty)
    }

    @Test(arguments: [DiagnosticTool.arcleak, .dolly, .deadwood])
    func `a tool that scopes its own report with only blobs not on disk is skipped`(tool: DiagnosticTool) async throws {
        // Without its files such a tool would report the whole root, so it does not run at all.
        let temp = TemporaryDirectory(prefix: "diageng")
        defer { temp.cleanup() }
        let root = URL(filePath: temp.file("root"))
        let executable = URL(filePath: temp.file("tool/\(tool.executableName)"))
        try DiagnosticsEngineTests.makeExecutable(at: executable)
        let runner = FakeProcessRunner(always: .success(""))
        let discovery = DiagnosticsEngineTests.discovery(
            runner: runner, executable: executable, home: URL(filePath: temp.file("home")))
        let engine = DiagnosticsEngine(runner: runner, discovery: discovery)

        let file = DiagnosticsEngine.FileTarget(path: "A.swift", contentHash: "a", url: nil)
        let request = DiagnosticsEngineTests.request(
            root: root, files: [file], corpusFingerprint: "fp-1", tool: tool, customPath: executable.path)
        let result = try await engine.run(tool, request: request)
        #expect(result.status == .skipped("sources not on disk"))
        #expect(runner.specs.isEmpty)
    }

    @Test(arguments: [DiagnosticTool.arcleak, .dolly, .deadwood])
    func `cachedResult answers nothing for a self-scoping tool with no files, since run decides it`(
        tool: DiagnosticTool
    ) async throws {
        let temp = TemporaryDirectory(prefix: "diageng")
        defer { temp.cleanup() }
        let root = URL(filePath: temp.file("root"))
        let executable = URL(filePath: temp.file("tool/\(tool.executableName)"))
        try DiagnosticsEngineTests.makeExecutable(at: executable)
        let runner = FakeProcessRunner(always: .success(""))
        let discovery = DiagnosticsEngineTests.discovery(
            runner: runner, executable: executable, home: URL(filePath: temp.file("home")))
        let engine = DiagnosticsEngine(runner: runner, discovery: discovery)

        let request = DiagnosticsEngineTests.request(
            root: root, files: [], corpusFingerprint: "fp-1", tool: tool, customPath: executable.path)
        #expect(await engine.cachedResult(tool, request: request) == nil)
        #expect(runner.specs.isEmpty)
    }

    @Test(arguments: [DiagnosticTool.arcleak, .dolly, .deadwood])
    func `a self-scoping tool with no files reports toolMissing when it cannot be located`(
        tool: DiagnosticTool
    ) async throws {
        let temp = TemporaryDirectory(prefix: "diageng")
        defer { temp.cleanup() }
        let root = URL(filePath: temp.file("root"))
        let runner = FakeProcessRunner(always: .success(""))
        let discovery = ToolDiscovery(
            runner: runner, bundledDirectory: nil, homeDirectory: URL(filePath: temp.file("home")),
            environment: [:])
        let engine = DiagnosticsEngine(runner: runner, discovery: discovery)

        // Nothing is installed at any rung of discovery, so the missing tool shows even though no file changed.
        let request = DiagnosticsEngine.Request(root: root, files: [], corpusFingerprint: "fp-1", tools: [:])
        let result = try await engine.run(tool, request: request)
        #expect(result.status == .toolMissing)
        #expect(result.findings.isEmpty)
    }

    @Test
    func `a corpus tool with no files still launches once over the root, with its findings filtered to none`()
        async throws
    {
        let temp = TemporaryDirectory(prefix: "diageng")
        defer { temp.cleanup() }
        let root = URL(filePath: temp.file("root"))
        let executable = URL(filePath: temp.file("tool/swiftlint"))
        try DiagnosticsEngineTests.makeExecutable(at: executable)
        // The report names A.swift, which the request does not name, so the post-filter removes it.
        let runner = FakeProcessRunner(always: DiagnosticsEngineTests.sarifOutput(root: root))
        let discovery = DiagnosticsEngineTests.discovery(
            runner: runner, executable: executable, home: URL(filePath: temp.file("home")))
        let engine = DiagnosticsEngine(runner: runner, discovery: discovery)

        let request = DiagnosticsEngineTests.request(
            root: root, files: [], corpusFingerprint: "fp-1", tool: .swiftlint, customPath: executable.path)
        let result = try await engine.run(.swiftlint, request: request)

        #expect(result.status == .succeeded)
        #expect(result.findings.isEmpty)
        #expect(runner.specs.count == 1)
        let launch = try #require(runner.specs.first)
        #expect(launch.arguments == ["lint", "--reporter", "sarif", "--quiet"])
    }
}

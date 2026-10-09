import AemiTestKit
import AtelierProcess
import AtelierTestSupport
import Foundation
import Testing

@testable import AtelierDiagnostics

/// ``DiagnosticsEngine`` over a tool that scopes its own report to the request's files: it is given those files, keeps
/// the findings it reports as written, is cached per set of files, and is skipped when it has none.
struct DiagnosticsEngineScopeTests {
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
                "analyze", root.path, "--only", root.appending(path: "A.swift").path, "--format", "sarif",
                "--relative-to", root.path
            ])
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
    func `a tool that scopes its own report with no files is skipped without being launched`(tool: DiagnosticTool)
        async throws
    {
        let temp = TemporaryDirectory(prefix: "diageng")
        defer { temp.cleanup() }
        let root = URL(filePath: temp.file("root"))
        let executable = URL(filePath: temp.file("tool/\(tool.executableName)"))
        try DiagnosticsEngineTests.makeExecutable(at: executable)
        let runner = FakeProcessRunner(always: .success(""))
        let discovery = DiagnosticsEngineTests.discovery(
            runner: runner, executable: executable, home: URL(filePath: temp.file("home")))
        let engine = DiagnosticsEngine(runner: runner, discovery: discovery)

        // A corpus is present, so only the empty file list can skip the run.
        let request = DiagnosticsEngineTests.request(
            root: root, files: [], corpusFingerprint: "fp-1", tool: tool, customPath: executable.path)
        let result = try await engine.run(tool, request: request)
        #expect(result.status == .skipped("no files"))
        #expect(result.findings.isEmpty)
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
}

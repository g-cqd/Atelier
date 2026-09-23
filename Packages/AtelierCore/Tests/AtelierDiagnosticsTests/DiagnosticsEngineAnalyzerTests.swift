import AemiTestKit
import AtelierProcess
import AtelierTestSupport
import Foundation
import Testing

@testable import AtelierDiagnostics

/// ``DiagnosticsEngine`` over arcleak, dolly and deadwood: SARIF shaped like theirs keeps every finding on the files
/// the request names, arcleak reads the whole root, and an exit 70 counts only when its SARIF parses.
struct DiagnosticsEngineAnalyzerTests {
    /// The request's files: `files`, root-relative, each on disk under `root`.
    private static func fileTargets(_ files: [String], under root: URL) -> [DiagnosticsEngine.FileTarget] {
        files.map { DiagnosticsEngine.FileTarget(path: $0, contentHash: "hash-\($0)", url: root.appending(path: $0)) }
    }

    /// What dolly or deadwood reports on `repository`: two clone pairs, each with its twin as a related location, or
    /// fourteen unused declarations over every file.
    private static func analyzerEntries(
        for tool: DiagnosticTool, files: [String], in repository: AnalyzerRepository
    ) -> [AnalyzerSARIF.Entry] {
        let location = { (file: String, line: Int) in
            AnalyzerSARIF.Location(path: repository.reportedPath(file), line: line, column: 5)
        }
        guard tool == .deadwood else {
            return [3, 20]
                .map { line in
                    AnalyzerSARIF.Entry(
                        ruleID: "exact-clone", level: "warning", message: "Duplicate block",
                        location: location(files[0], line), related: [location(files[1], line + 2)],
                        relatedMessage: "duplicate region")
                }
        }
        return (0 ..< 14)
            .map { index in
                AnalyzerSARIF.Entry(
                    ruleID: "unused-function", level: "warning", message: "Unused function",
                    location: location(files[index % files.count], 1 + 3 * index))
            }
    }

    @Test(arguments: [(DiagnosticTool.dolly, 2), (.deadwood, 14)])
    func `every dolly or deadwood finding on a symlinked root with a space under TMPDIR survives the corpus filter`(
        tool: DiagnosticTool, expected: Int
    ) async throws {
        let files = ["Sources/Cache.swift", "Sources/Cache Copy.swift", "Sources/Unused.swift"]
        let repository = try AnalyzerRepository(files: files)
        defer { repository.cleanup() }
        let temp = TemporaryDirectory(prefix: "diageng")
        defer { temp.cleanup() }
        let executable = URL(filePath: temp.file("tool/\(tool.executableName)"))
        try DiagnosticsEngineTests.makeExecutable(at: executable)
        let sarif = try AnalyzerSARIF.log(
            tool: tool.rawValue, results: Self.analyzerEntries(for: tool, files: files, in: repository))
        let runner = FakeProcessRunner(always: .success(sarif))
        let discovery = DiagnosticsEngineTests.discovery(
            runner: runner, executable: executable, home: URL(filePath: temp.file("home")))
        let engine = DiagnosticsEngine(runner: runner, discovery: discovery)

        let result = try await engine.run(
            tool,
            request: DiagnosticsEngineTests.request(
                root: repository.root, files: Self.fileTargets(files, under: repository.root),
                corpusFingerprint: "fp-1", tool: tool, customPath: executable.path))

        #expect(result.status == .succeeded)
        #expect(result.findings.count == expected)
        #expect(result.findings.allSatisfy { files.contains($0.file) })
        #expect(result.findings.flatMap(\.related).allSatisfy { files.contains($0.file) })
    }

    @Test
    func `arcleak findings on a symlinked root with a space under TMPDIR name the request's own paths`() async throws {
        let files = ["Sources/Leak.swift"]
        let repository = try AnalyzerRepository(files: files)
        defer { repository.cleanup() }
        let temp = TemporaryDirectory(prefix: "diageng")
        defer { temp.cleanup() }
        let executable = URL(filePath: temp.file("tool/arcleak"))
        try DiagnosticsEngineTests.makeExecutable(at: executable)
        let sarif = try AnalyzerSARIF.log(
            tool: "arcleak",
            results: [
                AnalyzerSARIF.Entry(
                    ruleID: "stored-closure-strong-self", level: "warning", message: "Stored closure captures self",
                    location: AnalyzerSARIF.Location(path: repository.reportedPath(files[0]), line: 12, column: 9))
            ])
        let runner = FakeProcessRunner(always: .success(sarif))
        let discovery = DiagnosticsEngineTests.discovery(
            runner: runner, executable: executable, home: URL(filePath: temp.file("home")))
        let engine = DiagnosticsEngine(runner: runner, discovery: discovery)

        let result = try await engine.run(
            .arcleak,
            request: DiagnosticsEngineTests.request(
                root: repository.root, files: Self.fileTargets(files, under: repository.root), tool: .arcleak,
                customPath: executable.path))

        // Rows and cards look findings up by the request's root-relative paths.
        #expect(result.status == .succeeded)
        #expect(result.findings.map(\.file) == files)
    }

    @Test
    func `an arcleak run reads the whole root for five minutes and reports on the request's files, relative to it`()
        async throws
    {
        let temp = TemporaryDirectory(prefix: "diageng")
        defer { temp.cleanup() }
        let root = URL(filePath: temp.file("root"))
        let executable = URL(filePath: temp.file("tool/arcleak"))
        try DiagnosticsEngineTests.makeExecutable(at: executable)
        let runner = FakeProcessRunner(always: .success(#"{"version": "2.1.0", "runs": [{"results": []}]}"#))
        let discovery = DiagnosticsEngineTests.discovery(
            runner: runner, executable: executable, home: URL(filePath: temp.file("home")))
        let engine = DiagnosticsEngine(runner: runner, discovery: discovery)

        _ = try await engine.run(
            .arcleak,
            request: DiagnosticsEngineTests.request(
                root: root, files: Self.fileTargets(["A.swift", "B.swift"], under: root), tool: .arcleak,
                customPath: executable.path))

        let spec = try #require(runner.specs.first)
        #expect(
            spec.arguments == [
                "analyze", root.path, "--only", root.appending(path: "A.swift").path, "--only",
                root.appending(path: "B.swift").path, "--format", "sarif", "--relative-to", root.path
            ])
        #expect(spec.timeout == .seconds(300))
    }

    @Test(arguments: [DiagnosticTool.arcleak, .dolly, .deadwood])
    func `exit 70 with SARIF on standard output counts as a completed run`(tool: DiagnosticTool) async throws {
        let temp = TemporaryDirectory(prefix: "diageng")
        defer { temp.cleanup() }
        let root = URL(filePath: temp.file("root"))
        let executable = URL(filePath: temp.file("tool/\(tool.executableName)"))
        try DiagnosticsEngineTests.makeExecutable(at: executable)
        let sarif = try AnalyzerSARIF.log(
            tool: tool.rawValue,
            results: [
                AnalyzerSARIF.Entry(
                    ruleID: "\(tool.rawValue)/degraded-file", level: "note", message: "file skipped: over the size cap",
                    location: AnalyzerSARIF.Location(path: root.appending(path: "A.swift").path, line: 1, column: 1))
            ])
        let runner = FakeProcessRunner(
            always: ProcessOutput(
                terminationStatus: 70, standardOutput: Data(sarif.utf8),
                standardError: Data("\(tool.rawValue): every file in the corpus was skipped".utf8)))
        let discovery = DiagnosticsEngineTests.discovery(
            runner: runner, executable: executable, home: URL(filePath: temp.file("home")))
        let engine = DiagnosticsEngine(runner: runner, discovery: discovery)

        let result = try await engine.run(
            tool,
            request: DiagnosticsEngineTests.request(
                root: root, files: Self.fileTargets(["A.swift"], under: root), corpusFingerprint: "fp-1", tool: tool,
                customPath: executable.path))

        #expect(result.status == .succeeded)
        #expect(result.findings.map(\.file) == ["A.swift"])
    }

    @Test(arguments: [DiagnosticTool.arcleak, .dolly, .deadwood])
    func `exit 70 with nothing on standard output is a failure that carries standard error`(tool: DiagnosticTool)
        async throws
    {
        let temp = TemporaryDirectory(prefix: "diageng")
        defer { temp.cleanup() }
        let root = URL(filePath: temp.file("root"))
        let executable = URL(filePath: temp.file("tool/\(tool.executableName)"))
        try DiagnosticsEngineTests.makeExecutable(at: executable)
        let reason = "\(tool.rawValue): run cancelled before the corpus was complete; no findings reported"
        let runner = FakeProcessRunner(always: .failure(70, error: reason))
        let discovery = DiagnosticsEngineTests.discovery(
            runner: runner, executable: executable, home: URL(filePath: temp.file("home")))
        let engine = DiagnosticsEngine(runner: runner, discovery: discovery)

        let result = try await engine.run(
            tool,
            request: DiagnosticsEngineTests.request(
                root: root, files: Self.fileTargets(["A.swift"], under: root), corpusFingerprint: "fp-1", tool: tool,
                customPath: executable.path))

        #expect(result.status == .failed(reason))
        #expect(result.findings.isEmpty)
    }
}

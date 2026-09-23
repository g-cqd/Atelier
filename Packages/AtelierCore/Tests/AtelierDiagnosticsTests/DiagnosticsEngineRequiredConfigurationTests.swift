import AemiTestKit
import AtelierProcess
import AtelierTestSupport
import Foundation
import Testing

@testable import AtelierDiagnostics

/// ``DiagnosticsEngine``'s ``DiagnosticTool/requiredConfigurationFile`` gate: a tool whose configuration file is
/// missing at the analyzed root is skipped without running.
struct DiagnosticsEngineRequiredConfigurationTests {
    /// An executable file at `url` for discovery to find; the fake runner never spawns it.
    private static func makeExecutable(at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    /// A discovery with no bundle and an empty environment, so the request's custom path is what finds the tool.
    private static func discovery(runner: any ProcessRunner, home: URL) -> ToolDiscovery {
        ToolDiscovery(runner: runner, bundledDirectory: nil, homeDirectory: home, environment: [:])
    }

    private static func request(
        root: URL, files: [DiagnosticsEngine.FileTarget], corpusFingerprint: String? = nil,
        tool: DiagnosticTool, customPath: String
    ) -> DiagnosticsEngine.Request {
        DiagnosticsEngine.Request(
            root: root, files: files, corpusFingerprint: corpusFingerprint,
            tools: [tool: ToolLocation(customPath: customPath)]
        )
    }

    @Test
    func `swift-format is skipped when the project has no swift-format configuration`() async throws {
        let temp = TemporaryDirectory(prefix: "diageng")
        defer { temp.cleanup() }
        let root = URL(filePath: temp.file("root"))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let executable = URL(filePath: temp.file("tool/swift-format"))
        try Self.makeExecutable(at: executable)
        let runner = FakeProcessRunner(always: .success(""))
        let discovery = Self.discovery(runner: runner, home: URL(filePath: temp.file("home")))
        let engine = DiagnosticsEngine(runner: runner, discovery: discovery)

        let file = DiagnosticsEngine.FileTarget(
            path: "A.swift", contentHash: "a", url: root.appending(path: "A.swift"))
        let request = Self.request(root: root, files: [file], tool: .swiftFormat, customPath: executable.path)
        let result = try await engine.run(.swiftFormat, request: request)
        #expect(result.status == .skipped("no swift-format configuration in this project"))
        #expect(result.findings.isEmpty)
        #expect(runner.specs.isEmpty)
    }

    @Test
    func `swift-format runs when the project has a swift-format configuration`() async throws {
        let temp = TemporaryDirectory(prefix: "diageng")
        defer { temp.cleanup() }
        let root = URL(filePath: temp.file("root"))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "{}".write(to: root.appending(path: ".swift-format"), atomically: true, encoding: .utf8)
        let executable = URL(filePath: temp.file("tool/swift-format"))
        try Self.makeExecutable(at: executable)
        let runner = FakeProcessRunner(always: .success(""))
        let discovery = Self.discovery(runner: runner, home: URL(filePath: temp.file("home")))
        let engine = DiagnosticsEngine(runner: runner, discovery: discovery)

        let file = DiagnosticsEngine.FileTarget(
            path: "A.swift", contentHash: "a", url: root.appending(path: "A.swift"))
        let request = Self.request(root: root, files: [file], tool: .swiftFormat, customPath: executable.path)
        let result = try await engine.run(.swiftFormat, request: request)
        #expect(result.status == .succeeded)
        #expect(runner.specs.count == 1)
    }

    @Test
    func `swiftformat is skipped when the project has no dot-swiftformat configuration`() async throws {
        let temp = TemporaryDirectory(prefix: "diageng")
        defer { temp.cleanup() }
        let root = URL(filePath: temp.file("root"))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let executable = URL(filePath: temp.file("tool/swiftformat"))
        try Self.makeExecutable(at: executable)
        let runner = FakeProcessRunner(always: .success(""))
        let discovery = Self.discovery(runner: runner, home: URL(filePath: temp.file("home")))
        let engine = DiagnosticsEngine(runner: runner, discovery: discovery)

        let file = DiagnosticsEngine.FileTarget(
            path: "A.swift", contentHash: "a", url: root.appending(path: "A.swift"))
        let request = Self.request(
            root: root, files: [file], corpusFingerprint: "fp-1", tool: .swiftformat, customPath: executable.path)
        let result = try await engine.run(.swiftformat, request: request)
        #expect(result.status == .skipped("no SwiftFormat (Lockwood) configuration in this project"))
        #expect(result.findings.isEmpty)
        #expect(runner.specs.isEmpty)
    }

    @Test
    func `swiftformat runs when the project has a dot-swiftformat configuration`() async throws {
        let temp = TemporaryDirectory(prefix: "diageng")
        defer { temp.cleanup() }
        let root = URL(filePath: temp.file("root"))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "--exclude Generated".write(to: root.appending(path: ".swiftformat"), atomically: true, encoding: .utf8)
        let executable = URL(filePath: temp.file("tool/swiftformat"))
        try Self.makeExecutable(at: executable)
        let runner = FakeProcessRunner(always: .success(""))
        let discovery = Self.discovery(runner: runner, home: URL(filePath: temp.file("home")))
        let engine = DiagnosticsEngine(runner: runner, discovery: discovery)

        let file = DiagnosticsEngine.FileTarget(
            path: "A.swift", contentHash: "a", url: root.appending(path: "A.swift"))
        let request = Self.request(
            root: root, files: [file], corpusFingerprint: "fp-1", tool: .swiftformat, customPath: executable.path)
        let result = try await engine.run(.swiftformat, request: request)
        #expect(result.status == .succeeded)
        #expect(runner.specs.count == 1)
    }
}

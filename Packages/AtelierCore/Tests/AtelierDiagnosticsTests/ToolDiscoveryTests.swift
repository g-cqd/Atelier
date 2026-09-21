import AemiTestKit
import AtelierProcess
import AtelierTestSupport
import Foundation
import Testing

@testable import AtelierDiagnostics

/// ``ToolDiscovery``'s search precedence, its caches, and ``ToolDiscovery/invalidate()``.
struct ToolDiscoveryTests {
    /// Writes an executable shell script at `url` that prints `version` on its first line.
    private static func makeExecutable(at url: URL, version: String = "0.1.0") throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\necho \(version)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    /// A runner that answers an `xcrun --find` probe and a login-shell `$PATH` probe from fixed scripts, and
    /// records every spec it was given.
    private static func scriptedRunner(
        xcrunResult: ProcessOutput = .failure(1, error: "not found"), shellPathDirectories: [String] = []
    ) -> FakeProcessRunner {
        FakeProcessRunner { spec in
            if spec.executable.path == "/usr/bin/xcrun" { return xcrunResult }
            return .success(shellPathDirectories.joined(separator: ":"))
        }
    }

    @Test
    func `an environment override beats every other rung`() async throws {
        let temp = TemporaryDirectory(prefix: "toolloc")
        defer { temp.cleanup() }
        let overridden = URL(filePath: temp.file("override/tool"))
        let custom = URL(filePath: temp.file("custom/tool"))
        try Self.makeExecutable(at: overridden)
        try Self.makeExecutable(at: custom)

        let discovery = ToolDiscovery(
            runner: Self.scriptedRunner(), bundledDirectory: nil,
            homeDirectory: URL(filePath: temp.file("home")),
            environment: ["OVR": overridden.path]
        )
        let located = await discovery.locate(
            executableName: "tool", overrideVariable: "OVR", customPath: custom.path, searchesToolchain: false)
        #expect(located?.url == overridden)
        #expect(located?.origin == .environment)
    }

    @Test
    func `an override that is not executable is ignored, falling through to the custom path`() async throws {
        let temp = TemporaryDirectory(prefix: "toolloc")
        defer { temp.cleanup() }
        let custom = URL(filePath: temp.file("custom/tool"))
        try Self.makeExecutable(at: custom)

        let discovery = ToolDiscovery(
            runner: Self.scriptedRunner(), bundledDirectory: nil,
            homeDirectory: URL(filePath: temp.file("home")),
            environment: ["OVR": temp.file("nowhere/tool")]
        )
        let located = await discovery.locate(
            executableName: "tool", overrideVariable: "OVR", customPath: custom.path, searchesToolchain: false)
        #expect(located?.url == custom)
        #expect(located?.origin == .custom)
    }

    @Test
    func `a custom path beats the bundled directory, which beats the toolchain`() async throws {
        let temp = TemporaryDirectory(prefix: "toolloc")
        defer { temp.cleanup() }
        let bundled = URL(filePath: temp.file("bundle"))
        let bundledTool = bundled.appending(path: "tool")
        try Self.makeExecutable(at: bundledTool)
        let toolchainTool = URL(filePath: temp.file("toolchain/tool"))
        try Self.makeExecutable(at: toolchainTool)
        let runner = Self.scriptedRunner(xcrunResult: .success(toolchainTool.path + "\n"))

        // Bundled beats toolchain when no custom path is given.
        let withoutCustom = ToolDiscovery(
            runner: runner, bundledDirectory: bundled, homeDirectory: URL(filePath: temp.file("home")))
        let bundledWin = await withoutCustom.locate(
            executableName: "tool", overrideVariable: nil, customPath: nil, searchesToolchain: true)
        #expect(bundledWin?.url == bundledTool)
        #expect(bundledWin?.origin == .bundled)
        #expect(runner.specs.isEmpty)

        // A custom path beats that same bundled candidate.
        let custom = URL(filePath: temp.file("custom/tool"))
        try Self.makeExecutable(at: custom)
        let withCustom = ToolDiscovery(
            runner: runner, bundledDirectory: bundled, homeDirectory: URL(filePath: temp.file("home")))
        let customWin = await withCustom.locate(
            executableName: "tool", overrideVariable: nil, customPath: custom.path, searchesToolchain: true)
        #expect(customWin?.url == custom)
        #expect(customWin?.origin == .custom)
    }

    @Test
    func `the toolchain probe beats a well-known directory`() async throws {
        let temp = TemporaryDirectory(prefix: "toolloc")
        defer { temp.cleanup() }
        let home = URL(filePath: temp.file("home"))
        let wellKnown = home.appending(path: ".swiftly/bin/tool")
        try Self.makeExecutable(at: wellKnown)
        let toolchainTool = URL(filePath: temp.file("toolchain/tool"))
        try Self.makeExecutable(at: toolchainTool)
        let runner = Self.scriptedRunner(xcrunResult: .success(toolchainTool.path + "\n"))

        let discovery = ToolDiscovery(runner: runner, bundledDirectory: nil, homeDirectory: home)
        let located = await discovery.locate(
            executableName: "tool", overrideVariable: nil, customPath: nil, searchesToolchain: true)
        #expect(located?.url == toolchainTool)
        #expect(located?.origin == .toolchain)

        // Once removed from the toolchain (xcrun no longer reports it), the well-known directory wins instead.
        let secondRunner = Self.scriptedRunner(xcrunResult: .failure(1, error: "not found"))
        let secondDiscovery = ToolDiscovery(runner: secondRunner, bundledDirectory: nil, homeDirectory: home)
        let fallback = await secondDiscovery.locate(
            executableName: "tool", overrideVariable: nil, customPath: nil, searchesToolchain: true)
        #expect(fallback?.url == wellKnown)
        #expect(fallback?.origin == .wellKnown)
    }

    @Test
    func `a well-known directory beats the login shell PATH`() async throws {
        let temp = TemporaryDirectory(prefix: "toolloc")
        defer { temp.cleanup() }
        let home = URL(filePath: temp.file("home"))
        let wellKnown = home.appending(path: ".mint/bin/tool")
        try Self.makeExecutable(at: wellKnown)
        let shellDirectory = temp.file("shellpath")
        try Self.makeExecutable(at: URL(filePath: shellDirectory + "/tool"))
        let runner = Self.scriptedRunner(shellPathDirectories: [shellDirectory])

        let discovery = ToolDiscovery(runner: runner, bundledDirectory: nil, homeDirectory: home)
        let located = await discovery.locate(
            executableName: "tool", overrideVariable: nil, customPath: nil, searchesToolchain: false)
        #expect(located?.url == wellKnown)
        #expect(located?.origin == .wellKnown)
        // Found before the shell PATH rung, so the shell was never consulted.
        #expect(runner.specs.isEmpty)
    }

    @Test
    func `the login shell PATH is the last rung`() async throws {
        let temp = TemporaryDirectory(prefix: "toolloc")
        defer { temp.cleanup() }
        let home = URL(filePath: temp.file("home"))
        let shellDirectory = temp.file("shellpath")
        try Self.makeExecutable(at: URL(filePath: shellDirectory + "/tool"))
        let runner = Self.scriptedRunner(shellPathDirectories: [shellDirectory])

        let discovery = ToolDiscovery(runner: runner, bundledDirectory: nil, homeDirectory: home)
        let located = await discovery.locate(
            executableName: "tool", overrideVariable: nil, customPath: nil, searchesToolchain: false)
        #expect(located?.url == URL(filePath: shellDirectory + "/tool"))
        #expect(located?.origin == .shellPath)
    }

    @Test
    func `missing everywhere resolves to nil`() async throws {
        let temp = TemporaryDirectory(prefix: "toolloc")
        defer { temp.cleanup() }
        let home = URL(filePath: temp.file("home"))
        let discovery = ToolDiscovery(runner: Self.scriptedRunner(), bundledDirectory: nil, homeDirectory: home)
        let located = await discovery.locate(
            executableName: "ghost-tool", overrideVariable: nil, customPath: nil, searchesToolchain: true)
        #expect(located == nil)
    }

    @Test
    func `the login shell PATH is probed once across two locates`() async throws {
        let temp = TemporaryDirectory(prefix: "toolloc")
        defer { temp.cleanup() }
        let home = URL(filePath: temp.file("home"))
        let shellDirectory = temp.file("shellpath")
        try Self.makeExecutable(at: URL(filePath: shellDirectory + "/tool"))
        let runner = Self.scriptedRunner(shellPathDirectories: [shellDirectory])

        let discovery = ToolDiscovery(runner: runner, bundledDirectory: nil, homeDirectory: home)
        _ = await discovery.locate(
            executableName: "tool", overrideVariable: nil, customPath: nil, searchesToolchain: false)
        _ = await discovery.locate(
            executableName: "tool", overrideVariable: nil, customPath: nil, searchesToolchain: false)
        #expect(runner.specs.count == 1)
    }

    @Test
    func `a negative xcrun result is cached`() async throws {
        let temp = TemporaryDirectory(prefix: "toolloc")
        defer { temp.cleanup() }
        let home = URL(filePath: temp.file("home"))
        let runner = Self.scriptedRunner(xcrunResult: .failure(1, error: "not found"))

        let discovery = ToolDiscovery(runner: runner, bundledDirectory: nil, homeDirectory: home)
        let first = await discovery.locate(
            executableName: "ghost", overrideVariable: nil, customPath: nil, searchesToolchain: true)
        let second = await discovery.locate(
            executableName: "ghost", overrideVariable: nil, customPath: nil, searchesToolchain: true)
        #expect(first == nil)
        #expect(second == nil)
        #expect(runner.specs.filter { $0.executable.path == "/usr/bin/xcrun" }.count == 1)
    }

    @Test
    func `the version probe is cached by the executable's modification date`() async throws {
        let temp = TemporaryDirectory(prefix: "toolloc")
        defer { temp.cleanup() }
        let home = URL(filePath: temp.file("home"))
        let custom = URL(filePath: temp.file("custom/tool"))
        try Self.makeExecutable(at: custom, version: "1.2.3")
        let runner = FakeProcessRunner { spec in
            spec.executable == custom ? .success("1.2.3\n") : .failure(1, error: "not found")
        }

        let discovery = ToolDiscovery(runner: runner, bundledDirectory: nil, homeDirectory: home)
        let location = ToolLocation(customPath: custom.path)
        let first = await discovery.status(.swiftlint, location: location)
        let second = await discovery.status(.swiftlint, location: location)
        #expect(first.version == "1.2.3")
        #expect(second.version == "1.2.3")
        #expect(runner.specs.filter { $0.executable == custom }.count == 1)

        // Touching the file's modification date invalidates the cached version.
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: custom.path)
        _ = await discovery.status(.swiftlint, location: location)
        #expect(runner.specs.filter { $0.executable == custom }.count == 2)
    }

    @Test
    func `status reports nil for a tool found nowhere`() async throws {
        let temp = TemporaryDirectory(prefix: "toolloc")
        defer { temp.cleanup() }
        let home = URL(filePath: temp.file("home"))
        let discovery = ToolDiscovery(runner: Self.scriptedRunner(), bundledDirectory: nil, homeDirectory: home)
        let status = await discovery.status(.dolly, location: nil)
        #expect(status.url == nil)
        #expect(status.origin == nil)
        #expect(status.version == nil)
        #expect(!status.isAvailable)
    }

    @Test
    func `a disabled location resolves to nil without a lookup`() async throws {
        let temp = TemporaryDirectory(prefix: "toolloc")
        defer { temp.cleanup() }
        let home = URL(filePath: temp.file("home"))
        let custom = URL(filePath: temp.file("custom/tool"))
        try Self.makeExecutable(at: custom)
        let discovery = ToolDiscovery(runner: Self.scriptedRunner(), bundledDirectory: nil, homeDirectory: home)
        let located = await discovery.locate(
            .swiftlint, location: ToolLocation(isEnabled: false, customPath: custom.path))
        #expect(located == nil)
    }

    @Test
    func `invalidate drops the xcrun, shell-PATH and version caches`() async throws {
        let temp = TemporaryDirectory(prefix: "toolloc")
        defer { temp.cleanup() }
        let home = URL(filePath: temp.file("home"))
        let custom = URL(filePath: temp.file("custom/tool"))
        try Self.makeExecutable(at: custom)
        let runner = Self.scriptedRunner(xcrunResult: .failure(1, error: "not found"))

        let discovery = ToolDiscovery(runner: runner, bundledDirectory: nil, homeDirectory: home)
        let location = ToolLocation(customPath: custom.path)
        _ = await discovery.status(.swiftlint, location: location)
        _ = await discovery.locate(
            executableName: "ghost", overrideVariable: nil, customPath: nil, searchesToolchain: true)
        let callsBefore = runner.specs.count

        await discovery.invalidate()
        _ = await discovery.status(.swiftlint, location: location)
        _ = await discovery.locate(
            executableName: "ghost", overrideVariable: nil, customPath: nil, searchesToolchain: true)
        #expect(runner.specs.count > callsBefore)
    }
}

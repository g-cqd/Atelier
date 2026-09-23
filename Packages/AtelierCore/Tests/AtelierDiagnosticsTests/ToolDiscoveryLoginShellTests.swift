import AemiTestKit
import AtelierProcess
import AtelierTestSupport
import Foundation
import Testing

@testable import AtelierDiagnostics

/// ``ToolDiscovery``'s login-shell rung: how the shell is asked for its `PATH`, which entries are kept, and how one
/// probe serves every lookup that needs it.
struct ToolDiscoveryLoginShellTests {
    /// How long a wait may take before the test fails; a passing wait returns as soon as its event lands.
    private static let failureBound: Duration = .seconds(15)

    /// Writes an executable script at `url`.
    private static func makeExecutable(at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    /// `directory`, absolute, spelled relative to the process's working directory: enough `..` to reach `/`, then the
    /// rest, so it names the same directory wherever the tests run.
    private static func relativeSpelling(of directory: String) -> String {
        let depth = FileManager.default.currentDirectoryPath.split(separator: "/").count
        return String(repeating: "../", count: depth) + directory.dropFirst()
    }

    private static func locate(_ name: String, with discovery: ToolDiscovery) async -> (url: URL, origin: ToolOrigin)? {
        await discovery.locate(executableName: name, overrideVariable: nil, customPath: nil, searchesToolchain: false)
    }

    /// A file manager that records each executable check under `directory`, so a test can tell how far a lookup has
    /// run inside the discovery actor.
    private final class CheckRecordingFileManager: FileManager, @unchecked Sendable {
        let checks = AsyncEventProbe<String>()
        private let directory: String

        init(recordingUnder directory: String) {
            self.directory = directory
            super.init()
        }

        override func isExecutableFile(atPath path: String) -> Bool {
            if path.hasPrefix(directory + "/") { checks.record(path) }
            return super.isExecutableFile(atPath: path)
        }
    }

    @Test
    func `the login shell prints its exported PATH from the home directory`() async throws {
        let temp = TemporaryDirectory(prefix: "loginshell")
        defer { temp.cleanup() }
        let home = URL(filePath: temp.file("home"))
        let runner = FakeProcessRunner(always: .success(""))
        let discovery = ToolDiscovery(
            runner: runner, bundledDirectory: nil, homeDirectory: home,
            environment: ["SHELL": "/opt/homebrew/bin/fish"])

        _ = await Self.locate("atelier-probe", with: discovery)

        let spec = try #require(runner.specs.first)
        #expect(spec.executable == URL(filePath: "/opt/homebrew/bin/fish"))
        #expect(spec.arguments == ["-l", "-c", "/usr/bin/printenv PATH"])
        #expect(spec.currentDirectory == home)
    }

    @Test
    func `a SHELL that is not an absolute path falls back to zsh`() async throws {
        let temp = TemporaryDirectory(prefix: "loginshell")
        defer { temp.cleanup() }
        let runner = FakeProcessRunner(always: .success(""))
        let discovery = ToolDiscovery(
            runner: runner, bundledDirectory: nil, homeDirectory: URL(filePath: temp.file("home")),
            environment: ["SHELL": "fish"])

        _ = await Self.locate("atelier-probe", with: discovery)

        #expect(runner.specs.map(\.executable) == [URL(filePath: "/bin/zsh")])
    }

    @Test
    func `what the startup files print before the PATH line is skipped`() async throws {
        let temp = TemporaryDirectory(prefix: "loginshell")
        defer { temp.cleanup() }
        let shellDirectory = temp.file("fish-only")
        try Self.makeExecutable(at: URL(filePath: shellDirectory + "/atelier-probe"))
        // The directory leads the PATH line, so splitting the whole output on `:` would glue the noise to it.
        let output =
            "Welcome to fish, the friendly interactive shell\nnvm: using node v22\n\(shellDirectory):/usr/bin\n"
        let discovery = ToolDiscovery(
            runner: FakeProcessRunner(always: .success(output)), bundledDirectory: nil,
            homeDirectory: URL(filePath: temp.file("home")), environment: ["SHELL": "/opt/homebrew/bin/fish"])

        let located = await Self.locate("atelier-probe", with: discovery)

        #expect(located?.url == URL(filePath: shellDirectory + "/atelier-probe"))
        #expect(located?.origin == .shellPath)
    }

    @Test
    func `a relative, empty or dot PATH entry is never searched, even when it reaches the tool`() async throws {
        let temp = TemporaryDirectory(prefix: "loginshell")
        defer { temp.cleanup() }
        let toolDirectory = temp.file("bin")
        try Self.makeExecutable(at: URL(filePath: toolDirectory + "/atelier-probe"))
        let relative = Self.relativeSpelling(of: toolDirectory)
        // The relative entry does reach the tool from where the tests run.
        #expect(FileManager.default.isExecutableFile(atPath: relative + "/atelier-probe"))
        let discovery = ToolDiscovery(
            runner: FakeProcessRunner(always: .success(".::node_modules/.bin:\(relative)\n")), bundledDirectory: nil,
            homeDirectory: URL(filePath: temp.file("home")), environment: ["SHELL": "/bin/zsh"])

        #expect(await Self.locate("atelier-probe", with: discovery) == nil)
    }

    @Test
    func `a relative override or custom path is never used, even when it reaches the tool`() async throws {
        let temp = TemporaryDirectory(prefix: "loginshell")
        defer { temp.cleanup() }
        let tool = temp.file("bin/atelier-probe")
        try Self.makeExecutable(at: URL(filePath: tool))
        let relative = Self.relativeSpelling(of: tool)
        #expect(FileManager.default.isExecutableFile(atPath: relative))
        let discovery = ToolDiscovery(
            runner: FakeProcessRunner(always: .success("")), bundledDirectory: nil,
            homeDirectory: URL(filePath: temp.file("home")), environment: ["OVR": relative, "SHELL": "/bin/zsh"])

        let located = await discovery.locate(
            executableName: "atelier-probe", overrideVariable: "OVR", customPath: relative, searchesToolchain: false)

        #expect(located == nil)
    }

    /// Each lookup checks its well-known directories, `~/.local/bin` last, in the same actor turn that asks for the
    /// shell's `PATH`, so the third check means all three lookups have asked while the first probe is held.
    @Test
    func `three concurrent first lookups start one login shell`() async throws {
        let temp = TemporaryDirectory(prefix: "loginshell")
        defer { temp.cleanup() }
        let home = URL(filePath: temp.file("home"))
        let shellDirectory = temp.file("fish-only")
        for name in ["atelier-probe-a", "atelier-probe-b", "atelier-probe-c"] {
            try Self.makeExecutable(at: URL(filePath: shellDirectory + "/" + name))
        }
        let released = AsyncLatch()
        let runner = FakeProcessRunner { _ in
            try await released.wait()
            return .success(shellDirectory + "\n")
        }
        let fileManager = CheckRecordingFileManager(recordingUnder: home.appending(path: ".local/bin").path)
        let discovery = ToolDiscovery(
            runner: runner, bundledDirectory: nil, homeDirectory: home, environment: ["SHELL": "/bin/zsh"],
            fileManager: fileManager)

        async let first = Self.locate("atelier-probe-a", with: discovery)
        async let second = Self.locate("atelier-probe-b", with: discovery)
        async let third = Self.locate("atelier-probe-c", with: discovery)
        _ = try await fileManager.checks.wait(forAtLeast: 3, timeout: Self.failureBound)
        released.open()
        let located = await [first, second, third]

        #expect(located.map { $0?.origin } == [.shellPath, .shellPath, .shellPath])
        #expect(runner.specs.count == 1)
    }

    @Test
    func `a probe cancelled with its lookup is not cached, so the next lookup asks again`() async throws {
        let temp = TemporaryDirectory(prefix: "loginshell")
        defer { temp.cleanup() }
        let shellDirectory = temp.file("fish-only")
        try Self.makeExecutable(at: URL(filePath: shellDirectory + "/atelier-probe"))
        let started = AsyncLatch()
        let firstProbe = AsyncLatch()
        let runner = FakeProcessRunner { _ in
            if !firstProbe.isOpen {
                firstProbe.open()
                started.open()
                // Never opened: this probe ends only when its lookup is cancelled.
                try await AsyncLatch().wait()
            }
            return .success(shellDirectory + "\n")
        }
        let discovery = ToolDiscovery(
            runner: runner, bundledDirectory: nil, homeDirectory: URL(filePath: temp.file("home")),
            environment: ["SHELL": "/bin/zsh"])

        let cancelled = Task { await Self.locate("atelier-probe", with: discovery) }
        try await started.wait()
        cancelled.cancel()
        let cancelledResult = await cancelled.value
        let retried = await Self.locate("atelier-probe", with: discovery)

        #expect(cancelledResult == nil)
        #expect(retried?.origin == .shellPath)
        #expect(runner.specs.count == 2)
    }

    @Test
    func `a probe that started before invalidate does not fill the cache`() async throws {
        let temp = TemporaryDirectory(prefix: "loginshell")
        defer { temp.cleanup() }
        let shellDirectory = temp.file("fish-only")
        try Self.makeExecutable(at: URL(filePath: shellDirectory + "/atelier-probe"))
        let started = AsyncLatch()
        let released = AsyncLatch()
        let runner = FakeProcessRunner { _ in
            started.open()
            try await released.wait()
            return .success(shellDirectory + "\n")
        }
        let discovery = ToolDiscovery(
            runner: runner, bundledDirectory: nil, homeDirectory: URL(filePath: temp.file("home")),
            environment: ["SHELL": "/bin/zsh"])

        async let beforeInvalidate = Self.locate("atelier-probe", with: discovery)
        try await started.wait()
        await discovery.invalidate()
        released.open()
        _ = await beforeInvalidate
        _ = await Self.locate("atelier-probe", with: discovery)

        #expect(runner.specs.count == 2)
    }
}

import AemiTesting
import AtelierDiagnostics
import AtelierLSP
import AtelierTestSupport
import DiffGit
import Foundation
import Synchronization
import Testing

@testable import DiffComparison

/// ``ToolStatusBoard``: the Tools tab's statuses, and its Refresh finding a tool installed since the last probe
/// (TOOL-01 criterion 3).
@MainActor
@Suite(.mainActorLane)
struct ToolStatusBoardTests {
    private let scratchDefaults = ScratchDefaults(tag: "board")
    /// A second window's suite, so the tool the superseded refresh's window pins stays out of the newer one's.
    private let otherScratchDefaults = ScratchDefaults(tag: "board")

    @Test
    func `Refresh finds a tool the login shell's PATH gained since the last probe`() async throws {
        let temp = FileManager.default.temporaryDirectory.appending(
            path: "GitDiffViewerTests.board.\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: temp) }
        let installed = temp.appending(path: "bin", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
        let swiftlint = installed.appending(path: "swiftlint")
        try "#!/bin/sh\n".write(to: swiftlint, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: swiftlint.path)
        // The first login shell predates the install; every later one has the new directory on its PATH.
        let shells = Mutex(0)
        let runner = FakeProcessRunner { spec in
            guard spec.arguments == ["-l", "-c", "/usr/bin/printenv PATH"] else { return .failure(1, error: "") }
            let isFirst = shells.withLock { count in
                count += 1
                return count == 1
            }
            return .success(isFirst ? "/nonexistent\n" : installed.path + "\n")
        }
        let discovery = ToolDiscovery(
            runner: runner, bundledDirectory: nil, homeDirectory: temp.appending(path: "home"),
            environment: ["SHELL": "/bin/zsh"], wellKnownDirectories: [])
        let settings = ViewerSettings(defaults: scratchDefaults.defaults)
        let sut = ToolStatusBoard(discovery: discovery)
        await sut.refreshAll(for: settings, rediscovering: false)
        #expect(sut.statuses[DiagnosticTool.swiftlint.rawValue]?.isAvailable == false)

        await sut.refreshAll(for: settings, rediscovering: true)

        #expect(sut.statuses[DiagnosticTool.swiftlint.rawValue]?.url?.path == swiftlint.path)
    }

    @Test
    func `a refresh superseded by another writes no status of its own`() async throws {
        let temp = FileManager.default.temporaryDirectory.appending(
            path: "GitDiffViewerTests.board.\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: temp) }
        let pinned = temp.appending(path: "pinned/swiftformat")
        try FileManager.default.createDirectory(
            at: pinned.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\n".write(to: pinned, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: pinned.path)
        // The first xcrun probe, the older refresh's, holds until that refresh is cancelled.
        let firstProbe = TaskGate()
        let probes = Mutex(0)
        let runner = FakeProcessRunner { spec in
            guard spec.executable.path == "/usr/bin/xcrun" else { return .success("") }
            let isFirst = probes.withLock { count in
                count += 1
                return count == 1
            }
            if isFirst {
                firstProbe.open()
                // Never opened: this probe ends only when its refresh is cancelled.
                try await TaskGate().wait()
            }
            return .failure(1, error: "")
        }
        let discovery = ToolDiscovery(
            runner: runner, bundledDirectory: nil, homeDirectory: temp.appending(path: "home"),
            environment: ["SHELL": "/bin/zsh"], wellKnownDirectories: [])
        let older = ViewerSettings(defaults: scratchDefaults.defaults)
        older.toolLocations[.swiftformat] = ToolLocation(customPath: pinned.path)
        let newer = ViewerSettings(defaults: otherScratchDefaults.defaults)
        let sut = ToolStatusBoard(discovery: discovery)
        let olderRefresh = Task { await sut.refreshAll(for: older, rediscovering: false) }
        try await firstProbe.expectOpen()
        await sut.refreshAll(for: newer, rediscovering: false)

        olderRefresh.cancel()
        try await olderRefresh.expectValue()

        #expect(sut.statuses[DiagnosticTool.swiftformat.rawValue]?.isAvailable == false)
        #expect(!sut.isRefreshing)
    }

    @Test
    func `clangd is found through the toolchain, rust-analyzer in cargo's directory and basedpyright in ~/.local/bin`()
        async throws
    {
        let temp = FileManager.default.temporaryDirectory.appending(
            path: "GitDiffViewerTests.board.\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: temp) }
        let home = temp.appending(path: "home", directoryHint: .isDirectory)
        let installed = [
            "clangd": temp.appending(path: "toolchain/usr/bin/clangd"),
            "rust-analyzer": home.appending(path: ".cargo/bin/rust-analyzer"),
            "basedpyright": home.appending(path: ".local/bin/basedpyright-langserver")
        ]
        for executable in installed.values {
            try FileManager.default.createDirectory(
                at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "#!/bin/sh\n".write(to: executable, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        }
        let clangd = try #require(installed["clangd"])
        let runner = FakeProcessRunner { spec in
            guard spec.executable.path == "/usr/bin/xcrun", spec.arguments == ["--find", "clangd"] else {
                return .failure(1, error: "")
            }
            return .success(clangd.path + "\n")
        }
        let discovery = ToolDiscovery(
            runner: runner, bundledDirectory: nil, homeDirectory: home, environment: ["SHELL": "/bin/zsh"],
            wellKnownDirectories: [])
        let sut = ToolStatusBoard(discovery: discovery)

        await sut.refreshAll(for: ViewerSettings(defaults: scratchDefaults.defaults), rediscovering: false)

        for (id, executable) in installed {
            #expect(sut.statuses[id]?.url?.path == executable.path, "\(id)")
        }
        #expect(sut.statuses["clangd"]?.origin == .toolchain)
    }

    @Test
    func `each new language server's row names the languages it answers for`() {
        // The list's separators follow the locale.
        let clangd = ToolStatusBoard.footnote(for: .clangd)
        #expect(clangd.hasPrefix("Hover documentation runs it for C"))
        #expect(clangd.contains("C++") && clangd.contains("Objective-C") && !clangd.contains("objective-c"))
        #expect(
            ToolStatusBoard.footnote(for: .rustAnalyzer)
                == "Hover documentation runs it for Rust, whether or not diagnostics are on.")
        #expect(
            ToolStatusBoard.footnote(for: .basedPyright)
                == "Hover documentation runs it for Python, whether or not diagnostics are on.")
    }
}

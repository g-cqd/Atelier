import AemiTesting
import AtelierDiagnostics
import AtelierTestSupport
import DiffGit
import Foundation
import Synchronization
import Testing

@testable import DiffComparison

/// ``ToolStatusBoard``: the Tools tab's statuses, and its Refresh finding a tool installed since the last probe
/// (TOOL-01 criterion 3).
@MainActor
struct ToolStatusBoardTests {
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
        let settings = ViewerSettings(defaults: try Self.makeDefaults())
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
        let older = ViewerSettings(defaults: try Self.makeDefaults())
        older.toolLocations[.swiftformat] = ToolLocation(customPath: pinned.path)
        let newer = ViewerSettings(defaults: try Self.makeDefaults())
        let sut = ToolStatusBoard(discovery: discovery)
        let olderRefresh = Task { await sut.refreshAll(for: older, rediscovering: false) }
        try await firstProbe.wait()
        await sut.refreshAll(for: newer, rediscovering: false)

        olderRefresh.cancel()
        await olderRefresh.value

        #expect(sut.statuses[DiagnosticTool.swiftformat.rawValue]?.isAvailable == false)
        #expect(!sut.isRefreshing)
    }

    private static func makeDefaults() throws -> UserDefaults {
        let name = "GitDiffViewerTests.board.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}

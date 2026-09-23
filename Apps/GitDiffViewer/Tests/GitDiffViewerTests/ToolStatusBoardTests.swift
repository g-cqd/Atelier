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

    private static func makeDefaults() throws -> UserDefaults {
        let name = "GitDiffViewerTests.board.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}

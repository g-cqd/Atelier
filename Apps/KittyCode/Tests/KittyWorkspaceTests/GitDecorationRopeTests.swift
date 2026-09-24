import AemiTesting
import AtelierFileTree
import Foundation
import KittyGit
import Synchronization
import Testing

@testable import AtelierText
@testable import KittyWorkspace

private final class RopeDecorationSpy: RopeGitLineDecorationProvider, Sendable {
    let calls = Mutex((rope: 0, lines: 0))

    func lineDecorations(for _: String, lines _: [String]) async -> GitLineDecorations {
        calls.withLock { $0.lines += 1 }
        return .empty
    }

    func lineDecorations(for _: String, rope: Rope) async -> GitLineDecorations {
        calls.withLock { $0.rope += 1 }
        return GitLineDecorations(markers: [rope.lineCount - 1: .modified])
    }
}

@Suite @MainActor struct GitDecorationRopeTests {
    @Test func `refresh sends a rope snapshot without reading all lines on the main actor`() async throws {
        let workspace = WorkspaceSession(rootPath: "/project")
        let content = String(repeating: "a long line over the old gate\n", count: 31_000)
        workspace.bufferManager.open(
            filePath: "/project/large.txt", fileName: "large.txt", content: content, language: nil)
        workspace.restoreStateFromActiveBuffer()
        #expect(workspace.textBuffer._testSnapshotCachesAreEmpty)
        let provider = RopeDecorationSpy()
        let tasks = TaskProviderSpy(defaultTimeout: .seconds(15))
        let manager = GitDecorationManager(
            workspace: workspace,
            gitConfig: GitDecorationConfig(
                showGitStatus: true, showLineChanges: true, lineChangeDebounceMilliseconds: 0,
                maxLineDiffBytes: 8_000_000),
            gitLineDecorationProvider: provider, invalidateRender: {}, taskProvider: tasks)
        manager.scheduleRefreshForActiveBuffer(debounced: false)
        try await tasks.waitForAllTasks()
        manager.stop()
        #expect(provider.calls.withLock { $0.rope } == 1)
        #expect(provider.calls.withLock { $0.lines } == 0)
        #expect(workspace.textBuffer._testSnapshotCachesAreEmpty)
        #expect(workspace.bufferManager.activeBuffer?.gitLineDecorations.markers[31_000] == .modified)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["GDV_BENCH"] != nil))
    func `gutter snapshot benchmark`() {
        var buffer = TextBuffer(String(repeating: "a long source line for the gutter\n", count: 100_000))
        var oldSamples: [Double] = []
        var newSamples: [Double] = []
        var total = 0
        for round in 0 ..< 9 {
            let operations: [(String, () -> Int)] = [
                ("before", { buffer.lines.count }),
                ("after", { buffer.ropeSnapshot.lineCount })
            ]
            for (name, operation) in round.isMultiple(of: 2) ? operations : operations.reversed() {
                if name == "before" { buffer.invalidateSnapshotCaches() }
                let start = ContinuousClock.now
                total += operation()
                let elapsed = start.duration(to: .now).components
                let milliseconds = Double(elapsed.seconds) * 1e3 + Double(elapsed.attoseconds) / 1e15
                if name == "before" { oldSamples.append(milliseconds) } else { newSamples.append(milliseconds) }
            }
        }
        #expect(total == 9 * 2 * buffer.lineCount)
        print("W3 gutter main actor before \(oldSamples.sorted()[4]) ms after \(newSamples.sorted()[4]) ms")
    }
}

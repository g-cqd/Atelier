import AemiTesting
import Foundation
import Observation
import Testing

@testable import KittyEditor

/// Release timings of reloading a changed file from disk, printed rather than asserted:
/// `GDV_BENCH=1 swift test -c release --filter ReloadBenchmark`. Each reload runs the command's own path, the read on
/// the state's pool and the install on the main actor, over a file that alternates between two versions; the main
/// actor's share alone is `EditorLargeFileBenchmark`'s.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["GDV_BENCH"] != nil))
@MainActor
struct ReloadBenchmark {
    /// Doc comments, declarations, strings, a block comment and a blank line, cycling; `version` changes one word in
    /// every declaration, so each reload replaces the text with different text.
    nonisolated private static func swiftLikeLine(_ index: Int, version: Int) -> String {
        switch index % 8 {
            case 0: "/// Returns the value for item \(index), clamped to the table."
            case 1: "public func compute\(index)(index: Int, name: String) -> Int { // v\(version)"
            case 2: "    let value = index &* \(index % 97) + name.utf8.count  // trailing note"
            case 3: "    guard value > 0 else { return 0 }"
            case 4: "    /* scratch \(index) */ let label = \"item \\(index) of \(index)\""
            case 5: "    return value + label.count"
            case 6: "}"
            default: ""
        }
    }

    private static func text(lineCount: Int, version: Int) -> Data {
        Data((0 ..< lineCount).map { swiftLikeLine($0, version: version) }.joined(separator: "\n").utf8)
    }

    private static func summary(_ samples: [Duration]) -> String {
        let milliseconds =
            samples.map {
                Double($0.components.seconds) * 1_000 + Double($0.components.attoseconds) / 1e15
            }
            .sorted()
        return String(
            format: "median %.1f ms, p10 %.1f, p90 %.1f, n %d", milliseconds[milliseconds.count / 2],
            milliseconds[milliseconds.count / 10], milliseconds[milliseconds.count * 9 / 10], milliseconds.count)
    }

    /// Returns once `state`'s status message satisfies `isDone`, woken by each change to it.
    private func waitForStatus(of state: EditorState, until isDone: (String) -> Bool) async {
        while !isDone(state.statusMessage) {
            await withCheckedContinuation { continuation in
                withObservationTracking {
                    _ = state.statusMessage
                } onChange: {
                    continuation.resume()
                }
            }
        }
    }

    /// Opens a `lineCount`-line Swift file as an open from the tree does, then reloads it after each change on disk,
    /// timing each reload from the command to the new text on screen, and to its highlights and width landing.
    private func measureReloads(lineCount: Int) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "reload-bench-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "large.swift")
        let versions = [Self.text(lineCount: lineCount, version: 0), Self.text(lineCount: lineCount, version: 1)]
        try versions[0].write(to: file)

        let tasks = TaskProviderSpy(defaultTimeout: .seconds(600))
        let state = EditorState(
            rootPath: directory.path, config: KittyConfig(), taskProvider: tasks, searchPool: EditorTestPool.shared)
        defer { state.shutdown() }
        state.lastRenderRows = 60
        state.openFileByPath(file.path)
        try await tasks.waitForSpawnedTasks(atLeast: 1)
        try await tasks.waitForAllTasks()
        #expect(state.fileLineCount == lineCount)

        let clock = ContinuousClock()
        var toText: [Duration] = []
        var toHighlights: [Duration] = []
        for index in 0 ..< 13 {
            try versions[(index + 1) % 2].write(to: file)
            state.statusMessage = ""
            let spawned = tasks.spawnedTaskCount
            let start = clock.now
            state.reloadActiveBufferFromDisk()
            await waitForStatus(of: state) { $0.hasSuffix("reloaded from disk") }
            let textShown = clock.now
            // The reload, then the post-load pass it hands the new text to.
            try await tasks.waitForSpawnedTasks(atLeast: spawned + 2)
            try await tasks.waitForAllTasks()
            let highlighted = clock.now
            #expect(state.highlightedLines.count == lineCount)
            // Two warm-up reloads.
            guard index >= 2 else { continue }
            toText.append(textShown - start)
            toHighlights.append(highlighted - start)
        }
        print("BENCH reload \(lineCount) lines, command to new text: \(Self.summary(toText))")
        print("BENCH reload \(lineCount) lines, command to highlights and width: \(Self.summary(toHighlights))")
    }

    @Test func `reloading a changed 100k-line file`() async throws {
        try await measureReloads(lineCount: 100_000)
    }

    @Test func `reloading a changed million-line file`() async throws {
        try await measureReloads(lineCount: 1_000_000)
    }
}

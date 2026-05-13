import Foundation
import Synchronization

public func searchWorkspace(
    pattern: SearchPattern,
    files: [String],
    openBuffers: [String: [String]],
    maxResults: Int = 5000,
    onProgress: @escaping @Sendable (SearchFileResult) -> Void
) async -> SearchRunResult {
    let clock = ContinuousClock()
    let startTime = clock.now

    let counters = SearchCounters()

    let workerCount = min(files.count, max(1, ProcessInfo.processInfo.activeProcessorCount))
    let chunkSize = max(1, (files.count + workerCount - 1) / workerCount)
    let chunks = stride(from: 0, to: files.count, by: chunkSize).map { start in
        Array(files[start..<min(start + chunkSize, files.count)])
    }

    await withTaskGroup(of: Void.self) { group in
        for chunk in chunks {
            group.addTask {
                for filePath in chunk {
                    guard !Task.isCancelled else { return }
                    guard !counters.hitCap else { return }

                    let lines: [String]
                    if let bufferLines = openBuffers[filePath] {
                        lines = bufferLines
                    } else {
                        guard let fileLines = readFileLines(at: filePath) else {
                            counters.incrementFilesSearched()
                            continue
                        }
                        lines = fileLines
                    }

                    counters.incrementFilesSearched()

                    let matches = findMatches(in: lines, pattern: pattern)
                    guard !matches.isEmpty else { continue }

                    let didHitCap = counters.addMatchesAndCheckCap(
                        matches.count, maxResults: maxResults)
                    counters.incrementFilesMatched()
                    if didHitCap { return }

                    let fileName = (filePath as NSString).lastPathComponent
                    let snippets = matches.prefix(20).map { match -> String in
                        guard match.row >= 0, match.row < lines.count else { return "" }
                        return lines[match.row].trimmingCharacters(in: .whitespaces)
                    }

                    let result = SearchFileResult(
                        filePath: filePath,
                        fileName: fileName,
                        matches: matches,
                        contextSnippets: Array(snippets)
                    )

                    counters.appendResult(result)
                    onProgress(result)
                }
            }
        }
    }

    let elapsed = clock.now - startTime
    let ms = elapsed.milliseconds

    let snapshot = counters.snapshot()
    return SearchRunResult(
        query: SearchQuery(text: ""),
        results: snapshot.results,
        totalMatchCount: snapshot.totalMatchCount,
        filesSearched: snapshot.filesSearched,
        filesMatched: snapshot.filesMatched,
        durationMilliseconds: ms,
        wasCancelled: Task.isCancelled
    )
}

private func readFileLines(at path: String) -> [String]? {
    guard let data = FileManager.default.contents(atPath: path),
        let content = String(data: data, encoding: .utf8)
    else { return nil }
    return content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
}

extension Duration {
    /// Whole-and-fractional milliseconds as a `Double`. Combines the seconds and
    /// attoseconds components in one place so call sites stay readable.
    var milliseconds: Double {
        Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15
    }
}

// MARK: - Thread-safe counters

private final class SearchCounters: Sendable {
    private struct State {
        var totalMatchCount: Int = 0
        var filesSearched: Int = 0
        var filesMatched: Int = 0
        var results: [SearchFileResult] = []
        var hitCap: Bool = false
    }

    private let mutex = Mutex(State())

    var hitCap: Bool {
        mutex.withLock { $0.hitCap }
    }

    func incrementFilesSearched() {
        mutex.withLock { $0.filesSearched += 1 }
    }

    func incrementFilesMatched() {
        mutex.withLock { $0.filesMatched += 1 }
    }

    /// Atomically adds `count` matches and returns `true` if this addition crossed
    /// the cap (so the caller should stop). Eliminates the TOCTOU window between
    /// adding matches and observing the cap.
    func addMatchesAndCheckCap(_ count: Int, maxResults: Int) -> Bool {
        mutex.withLock { state in
            state.totalMatchCount += count
            if state.totalMatchCount > maxResults {
                state.hitCap = true
            }
            return state.hitCap
        }
    }

    func appendResult(_ result: SearchFileResult) {
        mutex.withLock { $0.results.append(result) }
    }

    struct Snapshot {
        var totalMatchCount: Int
        var filesSearched: Int
        var filesMatched: Int
        var results: [SearchFileResult]
    }

    func snapshot() -> Snapshot {
        mutex.withLock { state in
            Snapshot(
                totalMatchCount: state.totalMatchCount,
                filesSearched: state.filesSearched,
                filesMatched: state.filesMatched,
                results: state.results
            )
        }
    }
}

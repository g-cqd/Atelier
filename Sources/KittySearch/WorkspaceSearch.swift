import Foundation

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

                    let currentTotal = counters.addMatches(matches.count)
                    if currentTotal > maxResults {
                        counters.hitCap = true
                    }
                    counters.incrementFilesMatched()

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
    let ms = Double(elapsed.components.attoseconds) / 1e15
        + Double(elapsed.components.seconds) * 1000

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

// MARK: - Thread-safe counters

private final class SearchCounters: @unchecked Sendable {
    private let lock = NSLock()
    private var _totalMatchCount: Int = 0
    private var _filesSearched: Int = 0
    private var _filesMatched: Int = 0
    private var _results: [SearchFileResult] = []
    private var _hitCap: Bool = false
    var hitCap: Bool {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _hitCap
        }
        set {
            lock.lock()
            _hitCap = newValue
            lock.unlock()
        }
    }

    func incrementFilesSearched() {
        lock.lock()
        _filesSearched += 1
        lock.unlock()
    }

    func incrementFilesMatched() {
        lock.lock()
        _filesMatched += 1
        lock.unlock()
    }

    @discardableResult
    func addMatches(_ count: Int) -> Int {
        lock.lock()
        _totalMatchCount += count
        let result = _totalMatchCount
        lock.unlock()
        return result
    }

    func appendResult(_ result: SearchFileResult) {
        lock.lock()
        _results.append(result)
        lock.unlock()
    }

    struct Snapshot {
        var totalMatchCount: Int
        var filesSearched: Int
        var filesMatched: Int
        var results: [SearchFileResult]
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(
            totalMatchCount: _totalMatchCount,
            filesSearched: _filesSearched,
            filesMatched: _filesMatched,
            results: _results
        )
    }
}

import AemiIO
import AemiKernels
import Foundation
import Synchronization
import System

public import class AemiRuntime.BlockingOffloadPool

public func searchWorkspace(
    pattern: SearchPattern,
    files: [String],
    openBuffers: [String: [String]],
    pool: BlockingOffloadPool,
    maxResults: Int = 5000,
    onProgress: @escaping @Sendable (SearchFileResult) -> Void
) async -> SearchRunResult {
    let clock = ContinuousClock()
    let startTime = clock.now

    let counters = SearchCounters()

    let workerCount = min(files.count, max(1, ProcessInfo.processInfo.activeProcessorCount))
    let chunkSize = max(1, (files.count + workerCount - 1) / workerCount)
    let chunks = stride(from: 0, to: files.count, by: chunkSize)
        .map { start in
            Array(files[start ..< min(start + chunkSize, files.count)])
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
                        guard let fileLines = await readFileLines(at: filePath, pool: pool) else {
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

                    let fileName = FilePath(filePath).lastComponent?.string ?? filePath
                    let snippets = matches.prefix(20)
                        .map { match -> String in
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

/// The file's lines, read through a read-only mapping so only each line's bytes are copied; nil when it cannot be
/// read. Runs on `pool`, since mapping and scanning the file block.
private func readFileLines(at path: String, pool: BlockingOffloadPool) async -> [String]? {
    try? await pool.run { readFileLinesBlocking(at: path) }
}

/// The blocking body of `readFileLines`; nil when the file cannot be opened, measured or mapped, as when it
/// vanished after enumeration.
private func readFileLinesBlocking(at path: String) -> [String]? {
    guard let file = try? PosixFile(path: path, mode: .readOnly) else { return nil }
    defer { file.close() }
    guard let size = try? file.fileSize() else { return nil }
    // `mmap` rejects a zero-length mapping; an empty file has exactly one (empty) line, matching
    // `"".split(separator: "\n", omittingEmptySubsequences: false) == [""]`.
    guard size > 0 else { return [""] }

    guard let map = try? RawFileMap(fileDescriptor: file.fileDescriptor, capacity: size) else {
        return nil
    }
    // The whole file is scanned once, front to back: let the kernel page it in ahead of the scan.
    map.prefetch(offset: 0, length: size)
    // `splitLines` runs inside the region's scope, so its raw pointer never outlives the mapping.
    return map.withRegion(offset: 0, count: size) { region in
        region.withUnsafeBytes { splitLines($0) }
    }
}

/// Splits a mapped file's bytes on `\n` like `String.split(separator: "\n", omittingEmptySubsequences: false)`: a
/// trailing `\n` yields a final empty line. `buffer` is valid only during the call, and no read leaves it.
private func splitLines(_ buffer: UnsafeRawBufferPointer) -> [String] {
    guard let base = buffer.baseAddress else { return [""] }
    let bytes = base.assumingMemoryBound(to: UInt8.self)
    let count = buffer.count
    var lines: [String] = []
    var lineStart = 0
    while true {
        if lineStart == count {
            lines.append("")
            return lines
        }
        let remaining = count - lineStart
        let relativeNewline = AemiKernels.firstIndexOfByte(
            base: bytes + lineStart, count: remaining, needle: 0x0A)
        let lineEnd = lineStart + relativeNewline
        lines.append(decodeLine(bytes, from: lineStart, to: lineEnd))
        if relativeNewline == remaining {
            return lines
        }
        lineStart = lineEnd + 1
    }
}

/// Decodes `bytes[start..<end]` as UTF-8, or an empty string when the bytes are invalid; `splitLines` only passes
/// bounds within its buffer.
private func decodeLine(_ bytes: UnsafePointer<UInt8>, from start: Int, to end: Int) -> String {
    guard end > start else { return "" }
    let slice = UnsafeBufferPointer(start: bytes + start, count: end - start)
    return String(validating: slice, as: UTF8.self) ?? ""
}

extension Duration {
    /// Whole and fractional milliseconds as a `Double`.
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

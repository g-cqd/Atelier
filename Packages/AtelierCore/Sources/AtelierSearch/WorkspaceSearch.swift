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

/// Audit A4 — `FileManager.contents(atPath:)` reads the whole file into a `Data`, then
/// `String(data:encoding:)` re-decodes into a UTF-8 String, then `split` allocates a `[String]` of
/// every line. Peak RSS per worker = ~3× the largest file in flight, multiplied by worker count.
///
/// The mapped version below opens the file through `PosixFile`, maps it read-only with
/// `RawFileMap`, and scans for `\n` with the SIMD `AemiKernels.firstIndexOfByte` kernel instead of a
/// byte-by-byte Swift loop or a `Data`-chunked scan. No chunk boundary bookkeeping is needed — the
/// whole file is one mapped region — and only each line's bytes are copied into a `String`, not the
/// whole file. This is blocking, syscall/mmap-bound work, so it always runs on `pool`
/// (`BlockingOffloadPool`), never inline on the cooperative pool that drives this task group.
private func readFileLines(at path: String, pool: BlockingOffloadPool) async -> [String]? {
    try? await pool.run { readFileLinesBlocking(at: path) }
}

/// The blocking body `readFileLines` offloads to `pool`. Returns `nil` when the file cannot be
/// opened, measured or mapped (deleted or permission-denied between enumeration and search —
/// matches the previous `FileHandle`-based `nil` return).
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
    // `withRegion`'s `RawSpan` is scoped to this closure (statically prevented from escaping the
    // mapping); `splitLines` runs entirely inside that scope, so the raw pointer it derives from
    // `withUnsafeBytes` never outlives the mapping.
    return map.withRegion(offset: 0, count: size) { region in
        region.withUnsafeBytes { splitLines($0) }
    }
}

/// Splits a mapped file's bytes on `\n`, matching `String.split(separator: "\n",
/// omittingEmptySubsequences: false)`: a trailing `\n` produces one extra empty element at the end.
///
/// Invariant: `buffer` is only valid for the duration of this call (handed in from
/// `RawFileMap.withRegion`'s scoped `RawSpan` via `withUnsafeBytes`, both of which return before this
/// function's caller does), and every offset read here — `lineStart` and `lineStart + relativeNewline`
/// — stays within `0...buffer.count` by construction of the loop below, so no read reaches past the
/// mapped region.
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

/// Decodes `bytes[start..<end]` as UTF-8, mirroring the previous `String(data:encoding:.utf8) ?? ""`
/// fallback for invalid byte sequences. `start` and `end` are always produced by the newline scan in
/// `splitLines`, so `0 <= start <= end <= count` holds for the same mapped buffer.
private func decodeLine(_ bytes: UnsafePointer<UInt8>, from start: Int, to end: Int) -> String {
    guard end > start else { return "" }
    let slice = UnsafeBufferPointer(start: bytes + start, count: end - start)
    return String(validating: slice, as: UTF8.self) ?? ""
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

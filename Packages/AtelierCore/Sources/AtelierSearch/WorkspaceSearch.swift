import AemiIO
import AemiKernels
import Foundation
import Synchronization
import System

public import class AemiRuntime.BlockingOffloadPool

/// Files larger than this are not searched: past it a file is a log, a dump or generated output, and every worker
/// would hold its whole text as lines.
public let maximumSearchedFileSize = 8 * 1024 * 1024

/// Searches `files` for `query`, each file read once, on `pool`.
/// - Parameters:
///   - query: What to find, reported back in the result; an empty query or an invalid regular expression finds nothing.
///   - files: Absolute paths, as ``enumerateSearchableFiles(rootPath:excludeGlobs:includeHidden:gitIgnoredPaths:)``
///     lists them.
///   - openBuffers: The lines of the files open in the editor, searched instead of what is on disk.
///   - pool: The threads files are read on, so that no cooperative thread waits on the disk.
///   - maxResults: The match count past which the search stops.
///   - maximumFileSize: Files larger than this are skipped, as are binary files, with a NUL among their first 8 KiB.
///   - onProgress: Called with each file's matches as the file is done.
/// - Returns: The matches of every file, with the counts and the query they answer.
public func searchWorkspace(
    query: SearchQuery,
    files: [String],
    openBuffers: [String: [String]],
    pool: BlockingOffloadPool,
    maxResults: Int = 5000,
    maximumFileSize: Int = maximumSearchedFileSize,
    onProgress: @escaping @Sendable (SearchFileResult) -> Void
) async -> SearchRunResult {
    let clock = ContinuousClock()
    let startTime = clock.now

    let counters = SearchCounters()
    guard let pattern = compilePattern(query) else {
        return SearchRunResult(
            query: query, results: [], totalMatchCount: 0, filesSearched: 0, filesMatched: 0, durationMilliseconds: 0,
            wasCancelled: Task.isCancelled)
    }

    // At least one worker, so that an empty file list divides by one.
    let workerCount = max(1, min(files.count, ProcessInfo.processInfo.activeProcessorCount))
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
                        guard
                            let fileLines = await readFileLines(
                                at: filePath, maximumSize: maximumFileSize, pool: pool)
                        else {
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
        query: query,
        results: snapshot.results,
        totalMatchCount: snapshot.totalMatchCount,
        filesSearched: snapshot.filesSearched,
        filesMatched: snapshot.filesMatched,
        durationMilliseconds: ms,
        wasCancelled: Task.isCancelled
    )
}

/// The file's lines, read on `pool`; nil when it is skipped. See ``searchableLines(of:maximumSize:)``.
private func readFileLines(at path: String, maximumSize: Int, pool: BlockingOffloadPool) async -> [String]? {
    try? await pool.run { readFileLinesBlocking(at: path, maximumSize: maximumSize) }
}

/// The blocking body of `readFileLines`; nil when the file cannot be opened, as when it vanished after enumeration,
/// or is skipped.
private func readFileLinesBlocking(at path: String, maximumSize: Int) -> [String]? {
    guard let file = try? PosixFile(path: path, mode: .readOnly) else { return nil }
    defer { file.close() }
    return searchableLines(of: file, maximumSize: maximumSize)
}

/// What a search's read asks of an open file: its size, then its bytes, copied with `pread` into memory the search
/// owns. A mapping would let another process that truncates the file between the two calls turn the next page
/// touched into SIGBUS; a short `pread` is an error instead. ``PosixFile`` is the one real conformer, and a test's
/// double truncates its file between the two calls.
protocol PositionalFile {
    func fileSize() throws -> Int
    func pread(into buffer: UnsafeMutableRawBufferPointer, at offset: Int) throws
}

extension PosixFile: PositionalFile {}

/// Bytes probed for a NUL, which marks a file as binary, as git and the file enumerator judge it.
let binaryProbeLength = 8192

/// The lines of `file`, read once with `pread` into memory this call owns; nil when the file is larger than
/// `maximumSize`, cannot be read to its end (it shrank after it was sized, say), or holds a NUL among its first
/// ``binaryProbeLength`` bytes. An empty file has one empty line, as
/// `"".split(separator: "\n", omittingEmptySubsequences: false)` does.
func searchableLines(of file: some PositionalFile, maximumSize: Int) -> [String]? {
    guard let size = try? file.fileSize(), size <= maximumSize else { return nil }
    guard size > 0 else { return [""] }
    var bytes = [UInt8](repeating: 0, count: size)
    return bytes.withUnsafeMutableBytes { buffer -> [String]? in
        guard (try? file.pread(into: buffer, at: 0)) != nil, let base = buffer.baseAddress else { return nil }
        let probe = min(buffer.count, binaryProbeLength)
        let firstNUL = AemiKernels.firstIndexOfByte(
            base: base.assumingMemoryBound(to: UInt8.self), count: probe, needle: 0)
        guard firstNUL == probe else { return nil }
        return splitLines(UnsafeRawBufferPointer(buffer))
    }
}

/// Splits a file's bytes on `\n` like `String.split(separator: "\n", omittingEmptySubsequences: false)`: a
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

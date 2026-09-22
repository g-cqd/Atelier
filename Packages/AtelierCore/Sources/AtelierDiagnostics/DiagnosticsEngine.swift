public import AtelierProcess
import Darwin
public import Foundation

/// Whether the calling thread is the process' main thread; used to assert the executor contract of
/// ``DiagnosticsEngine/parsedFindings(from:tool:root:)`` stays off it, in debug builds and under tests.
private func isOnMainThread() -> Bool {
    pthread_main_np() != 0
}

/// Runs each diagnostic tool as one cancellable, timeout-bounded job, parses its output into ``Finding``s, and
/// caches the full result per tool-version/config/payload combination so an unchanged run costs nothing to repeat.
public actor DiagnosticsEngine {
    /// One file offered to a per-file tool, or counted toward a corpus tool's payload fingerprint.
    public struct FileTarget: Sendable, Hashable {
        /// Analysis-root-relative, `/`-separated path, matching ``Finding/file``.
        public let path: String
        /// A hash of the file's content, used to detect a change without re-reading the file.
        public let contentHash: String
        /// Where the file lives on disk, or nil for a blob that has not been materialized there.
        public let url: URL?

        public init(path: String, contentHash: String, url: URL?) {
            self.path = path
            self.contentHash = contentHash
            self.url = url
        }
    }

    /// What to analyze, and which tools are enabled and where to find them.
    public struct Request: Sendable {
        public var root: URL
        public var files: [FileTarget]
        /// Identifies the working tree's current state for corpus-scoped tools; nil when there is no working tree
        /// to fingerprint, such as a comparison between two arbitrary sources.
        public var corpusFingerprint: String?
        public var tools: [DiagnosticTool: ToolLocation]

        public init(
            root: URL, files: [FileTarget], corpusFingerprint: String? = nil,
            tools: [DiagnosticTool: ToolLocation] = [:]
        ) {
            self.root = root
            self.files = files
            self.corpusFingerprint = corpusFingerprint
            self.tools = tools
        }
    }

    /// What became of one tool's run.
    public enum RunStatus: Sendable, Equatable {
        case succeeded
        case toolMissing
        case failed(String)
        case skipped(String)
    }

    /// One tool's outcome for a request.
    public struct ToolResult: Sendable {
        public let tool: DiagnosticTool
        public let findings: [Finding]
        public let status: RunStatus
        public let duration: Duration
        public let fromCache: Bool

        public init(tool: DiagnosticTool, findings: [Finding], status: RunStatus, duration: Duration, fromCache: Bool) {
            self.tool = tool
            self.findings = findings
            self.status = status
            self.duration = duration
            self.fromCache = fromCache
        }
    }

    /// Identifies a cached run: the exact tool binary (by path and modification date, since a reinstalled or
    /// updated tool must not reuse a stale result), its configuration, its analysis root (so two different
    /// repositories, or two windows on the same repository at two different worktree paths, never share a
    /// result), and its payload.
    private struct CacheKey: Hashable {
        let tool: DiagnosticTool
        let executablePath: String
        let executableModification: Date?
        let configFingerprint: String
        let root: String
        let payloadFingerprint: String
    }

    private let runner: any ProcessRunner
    private let discovery: ToolDiscovery
    private let clock: any Clock<Duration>
    private let fileManager = FileManager.default

    private var cache: [CacheKey: [Finding]] = [:]
    /// Recency order for the cache's simple LRU eviction, oldest first.
    private var cacheOrder: [CacheKey] = []
    private let cacheCapacity = 64

    public init(runner: any ProcessRunner, discovery: ToolDiscovery, clock: any Clock<Duration> = ContinuousClock()) {
        self.runner = runner
        self.discovery = discovery
        self.clock = clock
    }

    /// Runs `tool` over `request`, or answers from cache when nothing that would change its output has changed.
    /// - Throws: `CancellationError` when the calling task is cancelled; every other failure is reported through
    ///   the returned result's ``RunStatus/failed(_:)``.
    public func run(_ tool: DiagnosticTool, request: Request) async throws -> ToolResult {
        let scope = tool.scope

        if scope == .perFile, request.files.isEmpty {
            return ToolResult(tool: tool, findings: [], status: .skipped("no files"), duration: .zero, fromCache: false)
        }
        if scope == .corpus, request.corpusFingerprint == nil {
            return ToolResult(
                tool: tool, findings: [], status: .skipped("requires a working tree"), duration: .zero,
                fromCache: false)
        }
        if let requiredConfigurationFile = tool.requiredConfigurationFile,
            !fileManager.fileExists(atPath: request.root.appending(path: requiredConfigurationFile).path)
        {
            return ToolResult(
                tool: tool, findings: [],
                status: .skipped("no \(tool.displayName) configuration in this project"), duration: .zero,
                fromCache: false)
        }

        guard let located = await discovery.locate(tool, location: request.tools[tool]) else {
            return ToolResult(tool: tool, findings: [], status: .toolMissing, duration: .zero, fromCache: false)
        }

        let argvFiles: [String]
        if scope == .perFile {
            let onDisk = request.files.compactMap(\.url).map(\.path)
            if onDisk.isEmpty {
                return ToolResult(
                    tool: tool, findings: [], status: .skipped("sources not on disk"), duration: .zero,
                    fromCache: false)
            }
            argvFiles = onDisk
        } else {
            argvFiles = []
        }

        let cacheKey = cacheKey(for: tool, request: request, locatedPath: located.url.path)

        if let cached = cachedFindings(for: cacheKey) {
            return ToolResult(
                tool: tool, findings: filterFindings(cached, tool: tool, request: request), status: .succeeded,
                duration: .zero, fromCache: true)
        }

        let spec = ProcessSpec(
            executable: located.url, arguments: ToolCommand.analyze(tool, files: argvFiles, root: request.root),
            currentDirectory: request.root, timeout: .seconds(scope == .perFile ? 60 : 300)
        )

        var output: ProcessOutput?
        let duration: Duration
        do {
            duration = try await clock.measure {
                output = try await runner.run(spec)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return ToolResult(
                tool: tool, findings: [], status: .failed(String(describing: error)), duration: .zero,
                fromCache: false)
        }
        guard let output else {
            return ToolResult(
                tool: tool, findings: [], status: .failed("the run produced no result"), duration: duration,
                fromCache: false)
        }

        guard ToolCommand.acceptableExitCodes(tool).contains(output.terminationStatus) else {
            let message = output.errorText.isEmpty ? "exit \(output.terminationStatus)" : output.errorText
            return ToolResult(tool: tool, findings: [], status: .failed(message), duration: duration, fromCache: false)
        }

        let findings: [Finding]
        switch await Self.parsedFindings(from: output, tool: tool, root: request.root) {
            case .success(let parsed): findings = parsed
            case .failure(let failure):
                return ToolResult(
                    tool: tool, findings: [], status: .failed(failure.message), duration: duration, fromCache: false)
        }

        store(findings, for: cacheKey)
        return ToolResult(
            tool: tool, findings: filterFindings(findings, tool: tool, request: request), status: .succeeded,
            duration: duration, fromCache: false)
    }

    // MARK: - Fingerprints

    /// Builds `tool`'s cache key for `request`, run against the tool located at `locatedPath`. Pulled out of
    /// `run(_:request:)` so that function stays under the house style's length limit.
    private func cacheKey(for tool: DiagnosticTool, request: Request, locatedPath: String) -> CacheKey {
        CacheKey(
            tool: tool, executablePath: locatedPath, executableModification: modificationDate(ofItemAt: locatedPath),
            configFingerprint: configFingerprint(for: tool, root: request.root),
            root: canonicalRoot(request.root), payloadFingerprint: payloadFingerprint(for: tool, request: request))
    }

    /// A fingerprint of `tool`'s configuration files at `root`: each configured name's size and modification date,
    /// or `absent` when it does not exist. Any change to a config file busts the cache.
    private func configFingerprint(for tool: DiagnosticTool, root: URL) -> String {
        tool.configFileNames
            .map { name in
                let path = root.appending(path: name).path
                guard let attributes = try? fileManager.attributesOfItem(atPath: path) else { return "\(name)=absent" }
                let size = (attributes[.size] as? UInt64) ?? 0
                let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
                return "\(name)=\(size):\(modified)"
            }
            .joined(separator: "|")
    }

    /// `root`, resolved to an absolute, symlink-free path: two requests naming the same directory by different
    /// spellings (a relative path, a trailing slash, a symlinked worktree) must land on the same cache entries,
    /// and two different directories must never collide on this alone.
    private func canonicalRoot(_ root: URL) -> String {
        root.resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// A fingerprint of what is being analyzed: each file's path paired with its content hash (not the hashes
    /// alone) for a per-file tool, sorted by the pair so the fingerprint stays order-independent while still
    /// tying every hash to the path it was read from -- renaming a file to another path already present, or
    /// swapping two files' paths, changes at least one pair and so still busts the cache even though the set of
    /// hashes alone would not have; the corpus fingerprint as-is for a corpus tool.
    private func payloadFingerprint(for tool: DiagnosticTool, request: Request) -> String {
        switch tool.scope {
            case .perFile:
                request.files.map { "\($0.path)=\($0.contentHash)" }.sorted().joined(separator: ",")
            case .corpus: request.corpusFingerprint ?? ""
        }
    }

    /// Why a tool's output could not be decoded, carried as the message for ``RunStatus/failed(_:)``.
    private struct ParseFailure: Error {
        let message: String
    }

    /// The tool's output decoded per its format, off the main actor (SE-0461's `@concurrent`): a large SARIF
    /// payload or a big Xcode text log is real parsing work, freeing the engine's own actor to keep taking other
    /// tools' results while this one decodes.
    @concurrent
    private static func parsedFindings(
        from output: ProcessOutput, tool: DiagnosticTool, root: URL
    ) async -> Result<[Finding], ParseFailure> {
        assert(!isOnMainThread(), "parsedFindings must run off the main actor")
        switch tool.outputFormat {
            case .sarif:
                do {
                    return .success(try SARIFDecoder.findings(from: output.standardOutput, tool: tool, root: root))
                } catch {
                    return .failure(ParseFailure(message: String(describing: error)))
                }
            case .xcodeTextOnStderr:
                let stderrText = String(decoding: output.standardError, as: UTF8.self)
                let stdoutText = String(decoding: output.standardOutput, as: UTF8.self)
                return .success(
                    XcodeTextParser.findings(from: stderrText, tool: tool, root: root)
                        + XcodeTextParser.findings(from: stdoutText, tool: tool, root: root))
        }
    }

    /// Narrows a corpus tool's findings to the files the caller asked about; a per-file tool's cache key already
    /// pins the exact file set, so its findings need no filtering.
    private func filterFindings(_ findings: [Finding], tool: DiagnosticTool, request: Request) -> [Finding] {
        guard tool.scope == .corpus else { return findings }
        let paths = Set(request.files.map(\.path))
        return findings.filter { paths.contains($0.file) }
    }

    private func modificationDate(ofItemAt path: String) -> Date? {
        (try? fileManager.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    // MARK: - Cache

    private func cachedFindings(for key: CacheKey) -> [Finding]? {
        guard let findings = cache[key] else { return nil }
        touch(key)
        return findings
    }

    private func store(_ findings: [Finding], for key: CacheKey) {
        if cache[key] == nil {
            cacheOrder.append(key)
            if cacheOrder.count > cacheCapacity {
                let evicted = cacheOrder.removeFirst()
                cache.removeValue(forKey: evicted)
            }
        } else {
            touch(key)
        }
        cache[key] = findings
    }

    private func touch(_ key: CacheKey) {
        guard let index = cacheOrder.firstIndex(of: key) else { return }
        cacheOrder.remove(at: index)
        cacheOrder.append(key)
    }
}

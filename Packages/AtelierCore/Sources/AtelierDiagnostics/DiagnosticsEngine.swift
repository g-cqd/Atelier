public import AtelierProcess
public import Foundation

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

    /// What to analyze, and which tools are enabled and where to find them. Equatable, so a caller can tell an
    /// unchanged request from a new one and skip re-running it.
    public struct Request: Sendable, Equatable {
        public var root: URL
        public var files: [FileTarget]
        /// Identifies the working tree's current state for corpus-scoped tools; nil when there is no working tree
        /// to fingerprint, such as a comparison between two arbitrary sources.
        public var corpusFingerprint: String?
        public var tools: [DiagnosticTool: ToolLocation]
        /// What the tree under `root` holds, configuration files included, when that is known apart from where
        /// `root` is: a git tree id, for a ref exported into a throwaway folder. The cache is then keyed by it rather
        /// than by `root`'s path and its configuration files' dates, so a later export of the same tree answers from
        /// the cache, and ``DiagnosticsEngine/cachedResult(_:request:)`` can answer before any export.
        public var contentIdentity: String?

        public init(
            root: URL, files: [FileTarget], corpusFingerprint: String? = nil,
            tools: [DiagnosticTool: ToolLocation] = [:], contentIdentity: String? = nil
        ) {
            self.root = root
            self.files = files
            self.corpusFingerprint = corpusFingerprint
            self.tools = tools
            self.contentIdentity = contentIdentity
        }

        /// This request read from `folder` instead: the root and every file's location move there.
        public func rooted(at folder: URL) -> Request {
            var rooted = self
            rooted.root = folder
            rooted.files = files.map {
                FileTarget(path: $0.path, contentHash: $0.contentHash, url: folder.appending(path: $0.path))
            }
            return rooted
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

    /// Identifies a cached run: the tool binary by path and modification date, so an updated tool never reuses a
    /// result, its configuration, its analysis root, and its payload.
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

    /// What a cached run concluded: its findings, or, for a request identified by content, that it skipped for
    /// want of a configuration file, which only the files could tell.
    private enum CachedOutcome {
        case findings([Finding])
        case skipped(String)
    }

    private var cache: [CacheKey: CachedOutcome] = [:]
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

        if let skipped = Self.skippedWithoutRunning(tool, request: request) { return skipped }
        if request.contentIdentity == nil, !hasRequiredConfiguration(tool, at: request.root) {
            return Self.skippedForConfiguration(tool)
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

        if let cached = cachedOutcome(for: cacheKey) {
            return result(from: cached, tool: tool, request: request)
        }
        if request.contentIdentity != nil, !hasRequiredConfiguration(tool, at: request.root) {
            store(.skipped(Self.missingConfiguration(tool)), for: cacheKey)
            return Self.skippedForConfiguration(tool)
        }

        let spec = ProcessSpec(
            executable: located.url, arguments: ToolCommand.analyze(tool, files: argvFiles, root: request.root),
            currentDirectory: request.root, timeout: ToolCommand.timeout(tool)
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

        let exitStatus = output.terminationStatus
        let ranToCompletion = ToolCommand.acceptableExitCodes(tool).contains(exitStatus)
        guard ranToCompletion || ToolCommand.exitCodesAcceptedWithParsableOutput(tool).contains(exitStatus) else {
            return ToolResult(
                tool: tool, findings: [], status: .failed(Self.failureMessage(of: output)), duration: duration,
                fromCache: false)
        }

        let findings: [Finding]
        switch await Self.parsedFindings(from: output, tool: tool, root: request.root) {
            case .success(let parsed): findings = parsed
            case .failure(let failure):
                // A run that stopped short explains itself on standard error, not in the output it failed to write.
                let message = ranToCompletion ? failure.message : Self.failureMessage(of: output)
                return ToolResult(
                    tool: tool, findings: [], status: .failed(message), duration: duration, fromCache: false)
        }

        store(.findings(findings), for: cacheKey)
        return ToolResult(
            tool: tool, findings: filterFindings(findings, tool: tool, request: request), status: .succeeded,
            duration: duration, fromCache: false)
    }

    /// What ``run(_:request:)`` would answer for `tool` without running anything and without reading
    /// `request.root`: a skip or a missing tool it can tell from the request alone, or a result from the cache. Nil
    /// when the tool would have to run, so a caller that must first put the files on disk only does it then.
    public func cachedResult(_ tool: DiagnosticTool, request: Request) async -> ToolResult? {
        if let skipped = Self.skippedWithoutRunning(tool, request: request) { return skipped }
        if request.contentIdentity == nil, !hasRequiredConfiguration(tool, at: request.root) {
            return Self.skippedForConfiguration(tool)
        }
        guard let located = await discovery.locate(tool, location: request.tools[tool]) else {
            return ToolResult(tool: tool, findings: [], status: .toolMissing, duration: .zero, fromCache: false)
        }
        let key = cacheKey(for: tool, request: request, locatedPath: located.url.path)
        return cachedOutcome(for: key).map { result(from: $0, tool: tool, request: request) }
    }

    /// The result of a request that needs no run at all: a per-file tool with no file, or a corpus tool with no
    /// corpus to fingerprint.
    private static func skippedWithoutRunning(_ tool: DiagnosticTool, request: Request) -> ToolResult? {
        if tool.scope == .perFile, request.files.isEmpty {
            return ToolResult(tool: tool, findings: [], status: .skipped("no files"), duration: .zero, fromCache: false)
        }
        if tool.scope == .corpus, request.corpusFingerprint == nil {
            return ToolResult(
                tool: tool, findings: [], status: .skipped("requires a working tree"), duration: .zero,
                fromCache: false)
        }
        return nil
    }

    private static func skippedForConfiguration(_ tool: DiagnosticTool) -> ToolResult {
        ToolResult(
            tool: tool, findings: [], status: .skipped(missingConfiguration(tool)), duration: .zero, fromCache: false)
    }

    /// Why a tool that needs a configuration file did not run.
    private static func missingConfiguration(_ tool: DiagnosticTool) -> String {
        "no \(tool.displayName) configuration in this project"
    }

    /// Whether `root` carries the configuration file `tool` needs, or `tool` needs none.
    private func hasRequiredConfiguration(_ tool: DiagnosticTool, at root: URL) -> Bool {
        guard let requiredConfigurationFile = tool.requiredConfigurationFile else { return true }
        return fileManager.fileExists(atPath: root.appending(path: requiredConfigurationFile).path)
    }

    private func result(from outcome: CachedOutcome, tool: DiagnosticTool, request: Request) -> ToolResult {
        switch outcome {
            case .findings(let findings):
                ToolResult(
                    tool: tool, findings: filterFindings(findings, tool: tool, request: request), status: .succeeded,
                    duration: .zero, fromCache: true)
            case .skipped(let reason):
                ToolResult(tool: tool, findings: [], status: .skipped(reason), duration: .zero, fromCache: true)
        }
    }

    // MARK: - Fingerprints

    /// `tool`'s cache key for `request`, run with the binary at `locatedPath`.
    /// A request identified by content is keyed by that identity, which covers its configuration files, in place of
    /// its root and their dates: its root is a throwaway folder, and may not exist yet.
    private func cacheKey(for tool: DiagnosticTool, request: Request, locatedPath: String) -> CacheKey {
        CacheKey(
            tool: tool, executablePath: locatedPath, executableModification: modificationDate(ofItemAt: locatedPath),
            configFingerprint: request.contentIdentity == nil ? configFingerprint(for: tool, root: request.root) : "",
            root: request.contentIdentity.map { "content:\($0)" } ?? canonicalRoot(request.root),
            payloadFingerprint: payloadFingerprint(for: tool, request: request))
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

    /// `root` as an absolute, symlink-free path, so every spelling of one directory shares its cache entries.
    private func canonicalRoot(_ root: URL) -> String {
        root.resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// What is being analyzed: for a per-file tool the sorted `path=hash` pairs, so moving content between paths
    /// still changes it; for a corpus tool the corpus fingerprint.
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

    /// What a failed run printed on standard error, or its exit status when it printed nothing there.
    private static func failureMessage(of output: ProcessOutput) -> String {
        output.errorText.isEmpty ? "exit \(output.terminationStatus)" : output.errorText
    }

    /// The tool's output decoded per its format on the concurrent executor, so a large log never holds the engine.
    @concurrent
    private static func parsedFindings(
        from output: ProcessOutput, tool: DiagnosticTool, root: URL
    ) async -> Result<[Finding], ParseFailure> {
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

    /// Narrows a corpus tool's findings to the requested files; a per-file tool only ran on those.
    private func filterFindings(_ findings: [Finding], tool: DiagnosticTool, request: Request) -> [Finding] {
        guard tool.scope == .corpus else { return findings }
        let paths = Set(request.files.map(\.path))
        return findings.filter { paths.contains($0.file) }
    }

    private func modificationDate(ofItemAt path: String) -> Date? {
        (try? fileManager.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    // MARK: - Cache

    private func cachedOutcome(for key: CacheKey) -> CachedOutcome? {
        guard let outcome = cache[key] else { return nil }
        touch(key)
        return outcome
    }

    private func store(_ outcome: CachedOutcome, for key: CacheKey) {
        if cache[key] == nil {
            cacheOrder.append(key)
            if cacheOrder.count > cacheCapacity {
                let evicted = cacheOrder.removeFirst()
                cache.removeValue(forKey: evicted)
            }
        } else {
            touch(key)
        }
        cache[key] = outcome
    }

    private func touch(_ key: CacheKey) {
        guard let index = cacheOrder.firstIndex(of: key) else { return }
        cacheOrder.remove(at: index)
        cacheOrder.append(key)
    }
}

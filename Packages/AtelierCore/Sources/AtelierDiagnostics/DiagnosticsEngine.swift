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
            root: URL,
            files: [FileTarget],
            corpusFingerprint: String? = nil,
            tools: [DiagnosticTool: ToolLocation] = [:],
            contentIdentity: String? = nil
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
    struct CacheKey: Hashable {
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
    let fileManager = FileManager.default

    /// What a cached run concluded: its findings, or, for a request identified by content, that it skipped for
    /// want of a configuration file, which only the files could tell.
    enum CachedOutcome {
        case findings([Finding])
        case skipped(String)
    }

    var cache: [CacheKey: CachedOutcome] = [:]
    /// Recency order for the cache's simple LRU eviction, oldest first.
    var cacheOrder: [CacheKey] = []
    let cacheCapacity = 64

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

        if let settled = Self.resultWithoutRunning(tool, request: request) { return settled }
        if request.contentIdentity == nil, !hasRequiredConfiguration(tool, at: request.root) {
            return Self.skippedForConfiguration(tool)
        }

        guard let located = await discovery.locate(tool, location: request.tools[tool]) else {
            return ToolResult(tool: tool, findings: [], status: .toolMissing, duration: .zero, fromCache: false)
        }
        // Nothing to analyze, but only once the tool is known to be installed, so a missing tool still shows.
        if tool.scopesItsOwnReport, request.files.isEmpty {
            return ToolResult(tool: tool, findings: [], status: .succeeded, duration: .zero, fromCache: false)
        }

        let scopedPaths: [String]
        // A tool that scopes its own report is given the same files a per-file tool is.
        if scope == .perFile || tool.scopesItsOwnReport {
            let onDisk = request.files.compactMap(\.url).map(\.path)
            if onDisk.isEmpty {
                return Self.withoutFindings(tool, .skipped("sources not on disk"))
            }
            scopedPaths = onDisk
        } else {
            scopedPaths = []
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
            executable: located.url,
            arguments: ToolCommand.analyze(tool, files: scopedPaths, root: request.root),
            currentDirectory: request.root,
            standardInput: ToolCommand.standardInput(tool, files: scopedPaths),
            timeout: ToolCommand.timeout(tool)
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
            return Self.withoutFindings(tool, .failed(String(describing: error)))
        }
        guard let output else {
            return Self.withoutFindings(tool, .failed("the run produced no result"), duration: duration)
        }

        let exitStatus = output.terminationStatus
        let ranToCompletion = ToolCommand.acceptableExitCodes(tool).contains(exitStatus)
        guard ranToCompletion || ToolCommand.exitCodesAcceptedWithParsableOutput(tool).contains(exitStatus) else {
            return Self.withoutFindings(tool, .failed(Self.failureMessage(of: output)), duration: duration)
        }

        let findings: [Finding]
        switch await Self.parsedFindings(from: output, tool: tool, root: request.root) {
            case .success(let parsed): findings = parsed
            case .failure(let failure):
                // A run that stopped short explains itself on standard error, not in the output it failed to write.
                let message = ranToCompletion ? failure.message : Self.failureMessage(of: output)
                return Self.withoutFindings(tool, .failed(message), duration: duration)
        }

        store(.findings(findings), for: cacheKey)
        return ToolResult(
            tool: tool,
            findings: filterFindings(findings, tool: tool, request: request),
            status: .succeeded,
            duration: duration,
            fromCache: false
        )
    }

    /// A result for `tool` that found nothing, because it did not run or did not finish: what happened is `status`.
    private static func withoutFindings(_ tool: DiagnosticTool, _ status: RunStatus, duration: Duration = .zero)
        -> ToolResult
    {
        ToolResult(tool: tool, findings: [], status: status, duration: duration, fromCache: false)
    }

    /// What ``run(_:request:)`` would answer for `tool` without running anything and without reading
    /// `request.root`: a skip, a clean run, or a missing tool it can tell from the request alone, or a result from the
    /// cache. Nil when the tool would have to run, so a caller that must first put the files on disk only does it then.
    /// A tool that scopes its own report with no file is always nil, since ``run(_:request:)`` decides it once the tool
    /// is located.
    public func cachedResult(_ tool: DiagnosticTool, request: Request) async -> ToolResult? {
        if tool.scopesItsOwnReport, request.files.isEmpty { return nil }
        if let settled = Self.resultWithoutRunning(tool, request: request) { return settled }
        if request.contentIdentity == nil, !hasRequiredConfiguration(tool, at: request.root) {
            return Self.skippedForConfiguration(tool)
        }
        guard let located = await discovery.locate(tool, location: request.tools[tool]) else {
            return ToolResult(tool: tool, findings: [], status: .toolMissing, duration: .zero, fromCache: false)
        }
        let key = cacheKey(for: tool, request: request, locatedPath: located.url.path)
        return cachedOutcome(for: key).map { result(from: $0, tool: tool, request: request) }
    }

    /// The result of a request that needs no run at all: a corpus tool with no corpus to fingerprint, or a per-file tool
    /// with no file, which is skipped. A tool that scopes its own report with no file is not settled here: it is not
    /// skipped, and it is not launched over the whole root either. ``run(_:request:)`` reports its clean run once it has
    /// located the tool, so a missing tool still shows as missing.
    private static func resultWithoutRunning(_ tool: DiagnosticTool, request: Request) -> ToolResult? {
        if tool.scope == .corpus, request.corpusFingerprint == nil {
            return Self.withoutFindings(tool, .skipped("requires a working tree"))
        }
        guard request.files.isEmpty else { return nil }
        if tool.scope == .perFile, !tool.scopesItsOwnReport {
            return ToolResult(tool: tool, findings: [], status: .skipped("no files"), duration: .zero, fromCache: false)
        }
        return nil
    }

    private static func skippedForConfiguration(_ tool: DiagnosticTool) -> ToolResult {
        Self.withoutFindings(tool, .skipped(missingConfiguration(tool)))
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
                    tool: tool,
                    findings: filterFindings(findings, tool: tool, request: request),
                    status: .succeeded,
                    duration: .zero,
                    fromCache: true
                )
            case .skipped(let reason):
                ToolResult(tool: tool, findings: [], status: .skipped(reason), duration: .zero, fromCache: true)
        }
    }
}

public import Foundation

/// What runs one tool over one request: ``DiagnosticsEngine`` in production, a fake with controlled timing in tests.
public protocol DiagnosticsRunning: Sendable {
    func run(_ tool: DiagnosticTool, request: DiagnosticsEngine.Request) async throws -> DiagnosticsEngine.ToolResult

    /// What ``run(_:request:)`` would answer without running anything or reading the request's files; nil when the
    /// tool would have to run.
    func cachedResult(_ tool: DiagnosticTool, request: DiagnosticsEngine.Request) async
        -> DiagnosticsEngine.ToolResult?
}

extension DiagnosticsRunning {
    /// Nothing is known without running, by default.
    public func cachedResult(_ tool: DiagnosticTool, request: DiagnosticsEngine.Request) async
        -> DiagnosticsEngine.ToolResult?
    { nil }
}

extension DiagnosticsEngine: DiagnosticsRunning {}

/// Puts a request's files on disk in a folder of their own for as long as `body` runs, and removes them after: a git
/// ref exported into a private temporary folder, for one.
public typealias DiagnosticsMaterializer = @Sendable (_ body: @Sendable (URL) async throws -> Void) async throws -> Void

/// Runs the enabled tools of one request concurrently, one tool per child task, and reports each tool's outcome
/// as it lands.
///
/// The caller owns the task the run happens in, so cancelling it cancels every tool still in flight, and it paces
/// its own calls: nothing here debounces or supersedes a run.
public struct DiagnosticsSession: Sendable {
    /// One tool's outcome, and whether it was the last one still outstanding for its run.
    public struct Update: Sendable {
        public let result: DiagnosticsEngine.ToolResult
        public let isLast: Bool

        public init(result: DiagnosticsEngine.ToolResult, isLast: Bool) {
            self.result = result
            self.isLast = isLast
        }
    }

    private let engine: any DiagnosticsRunning

    public init(engine: any DiagnosticsRunning) {
        self.engine = engine
    }

    /// Runs the enabled tools of `request` concurrently and calls `onUpdate` once per tool as it finishes, returning
    /// once every one has reported. A cancelled tool reports nothing; any other failure arrives in its
    /// ``DiagnosticsEngine/ToolResult/status``.
    public func analyze(_ request: DiagnosticsEngine.Request, onUpdate: sending (Update) async -> Void) async {
        let enabledTools = Array(request.tools.filter(\.value.isEnabled).keys)
        guard !enabledTools.isEmpty else { return }

        var remaining = enabledTools.count
        await withTaskGroup(of: DiagnosticsEngine.ToolResult?.self) { group in
            for tool in enabledTools {
                group.addTask { try? await engine.run(tool, request: request) }
            }
            for await result in group {
                remaining -= 1
                guard let result else { continue }
                await onUpdate(Update(result: result, isLast: remaining == 0))
            }
        }
    }

    /// Runs the enabled tools of `request`, whose files are not on disk until `materialize` puts them there, and
    /// calls `onUpdate` once per tool as it lands. Every tool the engine can answer without the files, from its cache
    /// above all, reports first; `materialize` then runs once, only if a tool is left, and the rest run against the
    /// folder it provides. When the files cannot be put on disk, each tool left reports the failure.
    ///
    /// `request` should carry a ``DiagnosticsEngine/Request/contentIdentity``, so its results are cached by content
    /// rather than by a folder that is gone once the run ends.
    public func analyze(
        _ request: DiagnosticsEngine.Request, materializingWith materialize: DiagnosticsMaterializer,
        onUpdate: sending (Update) async -> Void
    ) async {
        let enabledTools = request.tools.filter(\.value.isEnabled).keys.sorted { $0.rawValue < $1.rawValue }
        var remaining = enabledTools.count
        var pending: [DiagnosticTool] = []
        for tool in enabledTools {
            guard let known = await engine.cachedResult(tool, request: request) else {
                pending.append(tool)
                continue
            }
            remaining -= 1
            await onUpdate(Update(result: known, isLast: remaining == 0))
        }
        guard !pending.isEmpty else { return }

        let (results, continuation) = AsyncStream.makeStream(of: DiagnosticsEngine.ToolResult.self)
        let engine = engine
        let tools = pending
        async let materialized: String? = Self.run(
            tools, of: request, materializingWith: materialize, engine: engine, into: continuation)
        var reported: Set<DiagnosticTool> = []
        for await result in results {
            reported.insert(result.tool)
            remaining -= 1
            await onUpdate(Update(result: result, isLast: remaining == 0))
        }
        guard let failure = await materialized else { return }
        for tool in tools where !reported.contains(tool) {
            remaining -= 1
            let result = DiagnosticsEngine.ToolResult(
                tool: tool, findings: [], status: .failed(failure), duration: .zero, fromCache: false)
            await onUpdate(Update(result: result, isLast: remaining == 0))
        }
    }

    /// Materializes `request`'s files and runs `tools` against them, yielding each result; returns why the files
    /// could not be put on disk, or nil once every tool ran.
    private static func run(
        _ tools: [DiagnosticTool], of request: DiagnosticsEngine.Request,
        materializingWith materialize: DiagnosticsMaterializer, engine: any DiagnosticsRunning,
        into continuation: AsyncStream<DiagnosticsEngine.ToolResult>.Continuation
    ) async -> String? {
        defer { continuation.finish() }
        do {
            try await materialize { folder in
                let rooted = request.rooted(at: folder)
                await withTaskGroup(of: DiagnosticsEngine.ToolResult?.self) { group in
                    for tool in tools {
                        group.addTask { try? await engine.run(tool, request: rooted) }
                    }
                    for await result in group {
                        if let result { continuation.yield(result) }
                    }
                }
            }
            return nil
        } catch is CancellationError {
            // A cancelled run reports nothing more, as a cancelled tool does.
            return nil
        } catch {
            return "the files could not be put on disk: \(error)"
        }
    }
}

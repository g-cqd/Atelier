/// What runs one tool over one request: ``DiagnosticsEngine`` in production, a fake with controlled timing in tests.
public protocol DiagnosticsRunning: Sendable {
    func run(_ tool: DiagnosticTool, request: DiagnosticsEngine.Request) async throws -> DiagnosticsEngine.ToolResult
}

extension DiagnosticsEngine: DiagnosticsRunning {}

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
}

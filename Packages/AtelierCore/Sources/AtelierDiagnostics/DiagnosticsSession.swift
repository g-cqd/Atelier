/// What runs one tool over one request; ``DiagnosticsEngine`` is the production conformance, so a test can
/// substitute a fake with controllable timing instead of spawning real processes.
public protocol DiagnosticsRunning: Sendable {
    func run(_ tool: DiagnosticTool, request: DiagnosticsEngine.Request) async throws -> DiagnosticsEngine.ToolResult
}

extension DiagnosticsEngine: DiagnosticsRunning {}

/// Runs the enabled tools of one request concurrently, one tool per child task, and reports each tool's outcome
/// as it lands. UI-agnostic so both apps in the workspace can share it behind their own adapters.
///
/// Caller-driven by design: there is no stored task, generation counter or debounce here. The caller structures
/// the run (a task group, or a task started from its own `TaskProvider`) and owns its lifetime — cancelling that
/// task cancels every tool still in flight. Pacing (debouncing bursts of calls, superseding an in-flight run)
/// belongs to the caller too, since only it knows the cadence its own inputs arrive at.
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

    /// Fans the enabled tools of `request` out concurrently and calls `onUpdate` once per tool as it finishes.
    /// Disabled tools (``ToolLocation/isEnabled`` false, or simply absent from `request.tools`) never run; an
    /// empty enabled set returns immediately without calling `onUpdate`.
    ///
    /// Returns once every enabled tool has reported. Cancelling the task this is awaited from cancels every
    /// tool still running; a cancelled tool's contribution is silently dropped rather than delivered, and every
    /// other failure is already carried in its ``DiagnosticsEngine/ToolResult/status``, not thrown.
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

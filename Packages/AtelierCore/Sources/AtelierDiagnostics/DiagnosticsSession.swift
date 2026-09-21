public import AemiRuntime

/// What runs one tool over one request; ``DiagnosticsEngine`` is the production conformance, so a test can
/// substitute a fake with controllable timing instead of spawning real processes.
public protocol DiagnosticsRunning: Sendable {
    func run(_ tool: DiagnosticTool, request: DiagnosticsEngine.Request) async throws -> DiagnosticsEngine.ToolResult
}

extension DiagnosticsEngine: DiagnosticsRunning {}

/// Runs the enabled tools for one comparison state, cancelling superseded runs; results stream back per tool as
/// each finishes. UI-agnostic so both apps in the workspace can share it behind their own adapters.
@MainActor
public final class DiagnosticsSession {
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
    private let taskProvider: any TaskProvider
    private let clock: any Clock<Duration>
    private let debounce: Duration

    /// Bumped by every ``analyze(_:)`` and ``cancel()``; work from an older generation is dropped when it lands.
    private var generation = 0
    private var task: Task<Void, Never>?

    public private(set) var isRunning = false

    /// Called on the main actor with each tool's result as it finishes.
    public var onUpdate: ((Update) -> Void)?
    /// Called on the main actor whenever a run starts or stops.
    public var onRunStateChanged: ((Bool) -> Void)?

    public init(
        engine: any DiagnosticsRunning, taskProvider: any TaskProvider,
        clock: any Clock<Duration> = ContinuousClock(), debounce: Duration = .milliseconds(250)
    ) {
        self.engine = engine
        self.taskProvider = taskProvider
        self.clock = clock
        self.debounce = debounce
    }

    /// Debounces, cancels the previous run, and fans the enabled tools of `request` out concurrently. Disabled
    /// tools (``ToolLocation/isEnabled`` false, or simply absent from `request.tools`) never run.
    ///
    /// An empty set of enabled tools is reported as a run that starts and immediately ends, with no updates: the
    /// caller still sees ``isRunning`` flip so it can clear stale findings, but nothing is debounced or fanned out
    /// since there would be nothing to cancel later.
    public func analyze(_ request: DiagnosticsEngine.Request) {
        task?.cancel()
        generation += 1
        let generation = generation

        let enabledTools = request.tools.filter(\.value.isEnabled).keys
        guard !enabledTools.isEmpty else {
            onRunStateChanged?(true)
            onRunStateChanged?(false)
            return
        }
        let tools = Array(enabledTools)
        let engine = engine
        let clock = clock
        let debounce = debounce

        task = taskProvider.task { [weak self] in
            try? await clock.sleep(for: debounce)
            guard !Task.isCancelled, let self, self.generation == generation else { return }
            self.isRunning = true
            self.onRunStateChanged?(true)

            var remaining = tools.count
            await withTaskGroup(of: DiagnosticsEngine.ToolResult?.self) { group in
                for tool in tools {
                    group.addTask {
                        // A cancelled tool run silently ends its contribution; every other failure is already
                        // carried in the result's status, not thrown.
                        try? await engine.run(tool, request: request)
                    }
                }
                for await result in group where self.generation == generation {
                    remaining -= 1
                    guard let result else { continue }
                    self.onUpdate?(Update(result: result, isLast: remaining == 0))
                }
            }

            guard self.generation == generation else { return }
            self.isRunning = false
            self.onRunStateChanged?(false)
        }
    }

    /// Stops the current run without starting another; no further updates are delivered for it.
    public func cancel() {
        task?.cancel()
        task = nil
        generation += 1
        guard isRunning else { return }
        isRunning = false
        onRunStateChanged?(false)
    }
}

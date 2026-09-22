import AemiTestKit
import Foundation
import Testing

@testable import AtelierDiagnostics

/// ``DiagnosticsSession``'s orchestration: fan-out, per-tool delivery and cancellation, exercised against a fake
/// ``DiagnosticsRunning`` whose per-tool timing is driven by a ``TestClock`` instead of real time. Debouncing and
/// superseding are the caller's responsibility now, so they are exercised in `DiagnosticsModelTests` instead.
struct DiagnosticsSessionTests {
    private static let root = URL(filePath: "/repo")

    private static func request(_ tools: [DiagnosticTool: ToolLocation]) -> DiagnosticsEngine.Request {
        DiagnosticsEngine.Request(root: root, files: [], corpusFingerprint: nil, tools: tools)
    }

    @Test
    func `each tool's finding delivers as it finishes, with isLast set on the final one`() async throws {
        let clock = TestClock()
        let runner = FakeDiagnosticsRunner(clock: clock)
        await runner.configure(.swiftlint, delay: .seconds(2))
        await runner.configure(.arcleak, delay: .seconds(1))
        let sut = DiagnosticsSession(engine: runner)
        let updateProbe = AsyncEventProbe<DiagnosticsSession.Update>()

        let analyzeTask = Task {
            await sut.analyze(Self.request([.swiftlint: ToolLocation(), .arcleak: ToolLocation()])) { update in
                updateProbe.record(update)
            }
        }

        // Both tools' delays are parked before either is released.
        try await clock.waitForSleepers(atLeast: 2)
        clock.advance(by: .seconds(1))
        // arcleak's one-second delay has elapsed; swiftlint's two-second one has not.
        _ = try await updateProbe.wait(forAtLeast: 1)
        clock.advance(by: .seconds(1))
        await analyzeTask.value

        let updates = updateProbe.events
        #expect(updates.map(\.result.tool) == [.arcleak, .swiftlint])
        #expect(updates.map(\.isLast) == [false, true])
    }

    @Test
    func `cancelling the awaiting task cancels every tool still in flight, delivering nothing further`()
        async throws
    {
        let clock = TestClock()
        let runner = FakeDiagnosticsRunner(clock: clock)
        await runner.configure(.swiftlint, delay: .seconds(1))
        let sut = DiagnosticsSession(engine: runner)
        let updateProbe = AsyncEventProbe<DiagnosticsSession.Update>()

        let analyzeTask = Task {
            await sut.analyze(Self.request([.swiftlint: ToolLocation()])) { update in updateProbe.record(update) }
        }
        try await clock.waitForSleepers(atLeast: 1)

        analyzeTask.cancel()
        _ = await analyzeTask.value
        clock.advance(by: .seconds(1))

        #expect(updateProbe.events.isEmpty)
    }

    @Test
    func `a disabled tool is never run`() async throws {
        let clock = TestClock()
        let runner = FakeDiagnosticsRunner(clock: clock)
        let sut = DiagnosticsSession(engine: runner)

        await sut.analyze(
            Self.request([.swiftlint: ToolLocation(isEnabled: false), .arcleak: ToolLocation(isEnabled: true)])
        ) { _ in }

        let calls = await runner.calls
        #expect(calls == [.arcleak])
    }

    @Test
    func `an empty enabled set returns immediately with no updates`() async throws {
        let clock = TestClock()
        let runner = FakeDiagnosticsRunner(clock: clock)
        let sut = DiagnosticsSession(engine: runner)
        var updates: [DiagnosticsSession.Update] = []

        await sut.analyze(Self.request([.swiftlint: ToolLocation(isEnabled: false)])) { updates.append($0) }

        #expect(updates.isEmpty)
    }
}

/// A ``DiagnosticsRunning`` whose per-tool completion is driven by a shared ``TestClock`` instead of real time, so
/// tests can pin the exact interleaving of a fan-out deterministically.
private actor FakeDiagnosticsRunner: DiagnosticsRunning {
    private let clock: TestClock
    private var delays: [DiagnosticTool: Duration] = [:]
    private(set) var calls: [DiagnosticTool] = []

    init(clock: TestClock) {
        self.clock = clock
    }

    func configure(_ tool: DiagnosticTool, delay: Duration) {
        delays[tool] = delay
    }

    func run(_ tool: DiagnosticTool, request: DiagnosticsEngine.Request) async throws -> DiagnosticsEngine.ToolResult {
        calls.append(tool)
        if let delay = delays[tool], delay > .zero {
            try await clock.sleep(for: delay)
        }
        return DiagnosticsEngine.ToolResult(
            tool: tool, findings: [], status: .succeeded, duration: .zero, fromCache: false)
    }
}

import AemiTestKit
import Foundation
import Testing

@testable import AtelierDiagnostics

/// ``DiagnosticsSession``'s orchestration: debouncing, superseding, fan-out and cancellation, exercised against a
/// fake ``DiagnosticsRunning`` whose per-tool timing is driven by a ``TestClock`` instead of real time.
@MainActor
struct DiagnosticsSessionTests {
    private static let root = URL(filePath: "/repo")

    private static func request(_ tools: [DiagnosticTool: ToolLocation]) -> DiagnosticsEngine.Request {
        DiagnosticsEngine.Request(root: root, files: [], corpusFingerprint: nil, tools: tools)
    }

    @Test
    func `superseding a run cancels its slow tool, which never delivers`() async throws {
        let clock = TestClock()
        let runner = FakeDiagnosticsRunner(clock: clock)
        await runner.configure(.swiftlint, delay: .seconds(1))
        let spy = TaskProviderSpy()
        let sut = DiagnosticsSession(engine: runner, taskProvider: spy, clock: clock, debounce: .milliseconds(10))
        var updates: [DiagnosticsSession.Update] = []
        sut.onUpdate = { updates.append($0) }

        sut.analyze(Self.request([.swiftlint: ToolLocation()]))
        try await clock.waitForSleepers(atLeast: 1)
        clock.advance(by: .milliseconds(10))
        try await clock.waitForSleepers(atLeast: 1)

        // Supersedes before swiftlint's one-second delay ever elapses.
        sut.analyze(Self.request([.arcleak: ToolLocation()]))
        try await clock.waitForSleepers(atLeast: 1)
        clock.advance(by: .milliseconds(10))
        try await spy.waitForAllTasks()

        #expect(updates.map(\.result.tool) == [.arcleak])
    }

    @Test
    func `each tool's finding delivers as it finishes, with isLast set on the final one`() async throws {
        let clock = TestClock()
        let runner = FakeDiagnosticsRunner(clock: clock)
        await runner.configure(.swiftlint, delay: .seconds(2))
        await runner.configure(.arcleak, delay: .seconds(1))
        let spy = TaskProviderSpy()
        let sut = DiagnosticsSession(engine: runner, taskProvider: spy, clock: clock, debounce: .milliseconds(10))
        var updates: [DiagnosticsSession.Update] = []
        let updateProbe = AsyncEventProbe<DiagnosticTool>()
        sut.onUpdate = {
            updates.append($0)
            updateProbe.record($0.result.tool)
        }

        sut.analyze(Self.request([.swiftlint: ToolLocation(), .arcleak: ToolLocation()]))
        try await clock.waitForSleepers(atLeast: 1)
        clock.advance(by: .milliseconds(10))
        // Both tools' delays are parked before either is released.
        try await clock.waitForSleepers(atLeast: 2)
        clock.advance(by: .seconds(1))
        // arcleak's one-second delay has elapsed; swiftlint's two-second one has not.
        _ = try await updateProbe.wait(forAtLeast: 1)
        clock.advance(by: .seconds(1))
        try await spy.waitForAllTasks()

        #expect(updates.map(\.result.tool) == [.arcleak, .swiftlint])
        #expect(updates.map(\.isLast) == [false, true])
    }

    @Test
    func `two analyze calls before the debounce elapses run once`() async throws {
        let clock = TestClock()
        let runner = FakeDiagnosticsRunner(clock: clock)
        let spy = TaskProviderSpy()
        let sut = DiagnosticsSession(engine: runner, taskProvider: spy, clock: clock, debounce: .milliseconds(10))
        var runStates: [Bool] = []
        sut.onRunStateChanged = { runStates.append($0) }

        sut.analyze(Self.request([.swiftlint: ToolLocation()]))
        try await clock.waitForSleepers(atLeast: 1)
        sut.analyze(Self.request([.swiftlint: ToolLocation()]))
        try await clock.waitForSleepers(atLeast: 1)
        clock.advance(by: .milliseconds(10))
        try await spy.waitForAllTasks()

        let calls = await runner.calls
        #expect(calls == [.swiftlint])
        #expect(runStates == [true, false])
    }

    @Test
    func `cancel stops delivery of a run still in flight`() async throws {
        let clock = TestClock()
        let runner = FakeDiagnosticsRunner(clock: clock)
        await runner.configure(.swiftlint, delay: .seconds(1))
        let spy = TaskProviderSpy()
        let sut = DiagnosticsSession(engine: runner, taskProvider: spy, clock: clock, debounce: .milliseconds(10))
        var updates: [DiagnosticsSession.Update] = []
        var runStates: [Bool] = []
        sut.onUpdate = { updates.append($0) }
        sut.onRunStateChanged = { runStates.append($0) }

        sut.analyze(Self.request([.swiftlint: ToolLocation()]))
        try await clock.waitForSleepers(atLeast: 1)
        clock.advance(by: .milliseconds(10))
        try await clock.waitForSleepers(atLeast: 1)

        sut.cancel()
        try await spy.waitForAllTasks()
        clock.advance(by: .seconds(1))
        try await spy.waitForAllTasks()

        #expect(updates.isEmpty)
        #expect(runStates == [true, false])
        #expect(!sut.isRunning)
    }

    @Test
    func `a disabled tool is never run`() async throws {
        let clock = TestClock()
        let runner = FakeDiagnosticsRunner(clock: clock)
        let spy = TaskProviderSpy()
        let sut = DiagnosticsSession(engine: runner, taskProvider: spy, clock: clock, debounce: .milliseconds(10))

        sut.analyze(
            Self.request([.swiftlint: ToolLocation(isEnabled: false), .arcleak: ToolLocation(isEnabled: true)]))
        try await clock.waitForSleepers(atLeast: 1)
        clock.advance(by: .milliseconds(10))
        try await spy.waitForAllTasks()

        let calls = await runner.calls
        #expect(calls == [.arcleak])
    }

    @Test
    func `an empty enabled set reports a run that starts and immediately ends, with no updates`() async throws {
        let clock = TestClock()
        let runner = FakeDiagnosticsRunner(clock: clock)
        let spy = TaskProviderSpy()
        let sut = DiagnosticsSession(engine: runner, taskProvider: spy, clock: clock, debounce: .milliseconds(10))
        var runStates: [Bool] = []
        var updates: [DiagnosticsSession.Update] = []
        sut.onRunStateChanged = { runStates.append($0) }
        sut.onUpdate = { updates.append($0) }

        sut.analyze(Self.request([.swiftlint: ToolLocation(isEnabled: false)]))

        #expect(runStates == [true, false])
        #expect(updates.isEmpty)
        #expect(!sut.isRunning)
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

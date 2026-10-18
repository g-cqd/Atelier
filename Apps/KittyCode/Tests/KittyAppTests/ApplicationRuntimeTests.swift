import AemiTesting
import Testing

@testable import KittyApp
@testable import KittyWidgets
@testable import TerminalKitCodecs
@testable import TerminalKitIO
@testable import TerminalKitInput

@Suite
struct ApplicationRuntimeTests {
    @Test
    @MainActor
    func `Setup writes expected escape sequences`() async throws {
        let mock = MockTerminalConnection()
        mock.feedInput([0x03])  // Ctrl+C (keyCode 3) to quit immediately

        let runtime = makeRuntime(mock)

        // Writes the setup sequences, then the cleanup once Ctrl+C ends the run.
        try await runtime.run(TestApp.self)

        let output = mock.writtenOutput
        // Should contain alternate screen entry bytes
        let altScreen = EscapeSequences.enterAlternateScreen
        let found = output.indices.contains(where: { i in
            output[i...].starts(with: altScreen)
        })
        #expect(found)
    }

    @Test
    @MainActor
    func `Run restores raw mode and writes cleanup sequences`() async throws {
        let mock = MockTerminalConnection()
        mock.feedInput([0x03])

        let runtime = makeRuntime(mock)

        try await runtime.run(TestApp.self)

        #expect(mock.enterRawModeCallCount == 1)
        #expect(mock.restoreModeCallCount == 1)
        #expect(!mock.isRawMode)
        #expect(containsSubsequence(EscapeSequences.popKeyboardMode, in: mock.writtenOutput))
        #expect(containsSubsequence(EscapeSequences.disableMouseSGR, in: mock.writtenOutput))
        #expect(containsSubsequence(EscapeSequences.disableFocusEvents, in: mock.writtenOutput))
        #expect(containsSubsequence(EscapeSequences.disableBracketedPaste, in: mock.writtenOutput))
        #expect(containsSubsequence(EscapeSequences.showCursor, in: mock.writtenOutput))
        #expect(containsSubsequence(EscapeSequences.leaveAlternateScreen, in: mock.writtenOutput))
    }

    @Test
    @MainActor
    func `configureInputSource can inject refresh events into the runtime loop`() async throws {
        let mock = MockTerminalConnection()
        let runtime = makeRuntime(mock)
        var events: [InputEvent] = []
        var renderCallCount = 0
        var refreshEventCount = 0

        try await runtime.run(
            render: { _ in
                renderCallCount += 1
            },
            onEvent: { event, _ in
                events.append(event)
                switch event {
                    case .refresh:
                        refreshEventCount += 1
                        return true
                    case .key(let key):
                        return key.keyCode != 3
                    default:
                        return true
                }
            },
            configureInputSource: { inputSource in
                inputSource.inject(.refresh)
                inputSource.inject(.key(KeyEvent(keyCode: 3)))
            }
        )

        #expect(renderCallCount == 1)
        #expect(refreshEventCount == 1)
        #expect(events.count == 2)
        let refreshEvent = try #require(events.first)
        if case .refresh = refreshEvent {
        } else {
            Issue.record("Expected .refresh, got \(refreshEvent)")
        }
        let lastEvent = try #require(events.last)
        guard case .key(let key) = lastEvent else {
            Issue.record("Expected .key, got \(lastEvent)")
            return
        }
        #expect(key.keyCode == 3)
    }

    @Test
    @MainActor
    func `a run stops the signal delivery it started`() async throws {
        let mock = MockTerminalConnection()
        mock.feedInput([0x03])
        let signals = SignalSessionSpy()

        try await makeRuntime(mock, signals: signals).run(TestApp.self)

        #expect(signals.startCount == 1)
        #expect(signals.stopCount == 1)
    }

    @Test
    @MainActor
    func `signal delivery that cannot start fails setup and still restores the terminal`() async {
        let mock = MockTerminalConnection()
        let signals = SignalSessionSpy(failingWith: .alreadyRunning)

        await #expect(throws: AppError.terminalSetupFailed("Could not install signal handlers: alreadyRunning")) {
            try await makeRuntime(mock, signals: signals).run(TestApp.self)
        }
        #expect(signals.startCount == 1)
        #expect(signals.stopCount == 0)
        #expect(mock.restoreModeCallCount == 1)
        #expect(!mock.isRawMode)
    }

    /// A runtime with a fixed environment and a signal spy in place of process-wide delivery.
    @MainActor
    private func makeRuntime(
        _ connection: MockTerminalConnection, signals: SignalSessionSpy = SignalSessionSpy()
    ) -> ApplicationRuntime {
        ApplicationRuntime(
            connection: connection, taskProvider: TaskProviderSpy(), environment: [:], makeSignals: signals.factory)
    }

    struct TestApp: App {
        var body: some View {
            Text("Test")
        }
    }

    private func containsSubsequence(_ subsequence: [UInt8], in bytes: [UInt8]) -> Bool {
        bytes.indices.contains { index in
            bytes[index...].starts(with: subsequence)
        }
    }
}

/// Whether a run draws pixel chrome: terminal detection with an environment override either way.
struct PixelChromeSelectionTests {
    private let size = TerminalSize(columns: 100, rows: 50, pixelWidth: 800, pixelHeight: 1000)

    @Test
    func `a capable terminal gets its cell size and an incapable one nothing`() {
        #expect(
            ApplicationRuntime.pixelChromeCell(environment: ["KITTY_WINDOW_ID": "1"], size: size)
                == .init(width: 8, height: 20))
        #expect(ApplicationRuntime.pixelChromeCell(environment: ["TERM_PROGRAM": "Apple_Terminal"], size: size) == nil)
        #expect(
            ApplicationRuntime.pixelChromeCell(
                environment: ["KITTY_WINDOW_ID": "1"], size: TerminalSize(columns: 80, rows: 24)) == nil)
    }

    @Test
    func `the environment can force pixel chrome off or on`() {
        #expect(
            ApplicationRuntime.pixelChromeCell(
                environment: ["KITTY_WINDOW_ID": "1", "KITTYCODE_PIXEL_CHROME": "0"], size: size) == nil)
        #expect(
            ApplicationRuntime.pixelChromeCell(environment: ["KITTYCODE_PIXEL_CHROME": "1"], size: size)
                == .init(width: 8, height: 20))
        #expect(
            ApplicationRuntime.pixelChromeCell(
                environment: ["KITTYCODE_PIXEL_CHROME": "1"], size: TerminalSize(columns: 80, rows: 24)) == nil)
    }
}

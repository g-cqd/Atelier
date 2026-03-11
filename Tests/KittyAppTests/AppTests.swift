import Testing
@testable import KittyApp
@testable import KittyInput
@testable import KittyWidgets
@testable import KittyTerminal
@testable import KittyCodecs

@Suite
struct AppProtocolTests {
    struct TestApp: App {
        var body: some View {
            Text("Test")
        }
    }

    @Test
    func `App instance can be created`() {
        let app = TestApp()
        _ = app.body
    }
}

@Suite
struct ApplicationRuntimeTests {
    @Test
    @MainActor
    func `Setup writes expected escape sequences`() async throws {
        let mock = MockTerminalConnection()
        mock.feedInput([0x03]) // Ctrl+C (keyCode 3) to quit immediately

        let runtime = ApplicationRuntime(connection: mock)

        // The runtime should write setup sequences and then cleanup
        // It will exit when it reads 'q'
        try await runtime.run(TestApp.self)

        let output = mock.writtenOutput
        // Should contain alternate screen entry bytes
        let altScreen = KittySequences.enterAlternateScreen
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

        let runtime = ApplicationRuntime(connection: mock)

        try await runtime.run(TestApp.self)

        #expect(mock.enterRawModeCallCount == 1)
        #expect(mock.restoreModeCallCount == 1)
        #expect(!mock.isRawMode)
        #expect(containsSubsequence(KittySequences.popKeyboardMode, in: mock.writtenOutput))
        #expect(containsSubsequence(KittySequences.disableMouseSGR, in: mock.writtenOutput))
        #expect(containsSubsequence(KittySequences.disableFocusEvents, in: mock.writtenOutput))
        #expect(containsSubsequence(KittySequences.disableBracketedPaste, in: mock.writtenOutput))
        #expect(containsSubsequence(KittySequences.showCursor, in: mock.writtenOutput))
        #expect(containsSubsequence(KittySequences.leaveAlternateScreen, in: mock.writtenOutput))
    }

    @Test
    @MainActor
    func `configureInputSource can inject refresh events into the runtime loop`() async throws {
        let mock = MockTerminalConnection()
        let runtime = ApplicationRuntime(connection: mock)
        var events: [InputEvent] = []
        var renderCount = 0

        try await runtime.run(
            render: { _ in
                renderCount += 1
            },
            onEvent: { event, _ in
                events.append(event)
                switch event {
                case .refresh:
                    renderCount += 1
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

        #expect(renderCount == 2)
        #expect(events.count == 2)
        let refreshEvent = try #require(events.first)
        guard case .refresh = refreshEvent else {
            throw RuntimeEventExpectationError.expectedRefresh
        }
        guard case .key(let key) = try #require(events.last) else {
            throw RuntimeEventExpectationError.expectedQuitKey
        }
        #expect(key.keyCode == 3)
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

private enum RuntimeEventExpectationError: Error {
    case expectedQuitKey
    case expectedRefresh
}

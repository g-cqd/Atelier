import Testing

@testable import KittyApp
@testable import KittyCodecs
@testable import KittyInput
@testable import KittyTerminal
@testable import KittyWidgets

@Suite
struct ApplicationRuntimeTests {
    @Test
    @MainActor
    func `Setup writes expected escape sequences`() async throws {
        let mock = MockTerminalConnection()
        mock.feedInput([0x03])  // Ctrl+C (keyCode 3) to quit immediately

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

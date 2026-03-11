import Testing
@testable import KittyApp
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

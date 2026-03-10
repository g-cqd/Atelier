import Testing
@testable import KittyApp
@testable import KittyWidgets
@testable import KittyTerminal
@testable import KittyCodecs

@Suite("App Protocol")
struct AppTests {
    struct TestApp: App {
        var body: some View {
            Text("Test")
        }
    }

    @Test("App instance can be created")
    func createApp() {
        let app = TestApp()
        _ = app.body
    }
}

@Suite("ApplicationRuntime")
struct ApplicationRuntimeTests {
    @Test("Setup writes expected escape sequences")
    @MainActor
    func setupSequences() async throws {
        let mock = MockTerminalConnection()
        mock.feedInput([0x71]) // 'q' to quit immediately

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

    struct TestApp: App {
        var body: some View {
            Text("Test")
        }
    }
}

import Testing

@testable import KittyApp
@testable import KittyWidgets
@testable import TerminalKitCodecs
@testable import TerminalKitIO
@testable import TerminalKitInput

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

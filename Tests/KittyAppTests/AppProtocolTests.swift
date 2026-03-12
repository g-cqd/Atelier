import Testing

@testable import KittyApp
@testable import KittyCodecs
@testable import KittyInput
@testable import KittyTerminal
@testable import KittyWidgets

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

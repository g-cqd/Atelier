import Foundation
import Testing

@testable import KittyRenderer
@testable import KittyWidgets

@Suite
struct ViewBuilderTests {
    @Test func `buildArray collects view loop items when wrapped in VStack`() {
        @ViewBuilder
        func make(items: [String]) -> some View {
            VStack {
                for item in items {
                    Text(item)
                }
            }
        }

        let view = make(items: ["a", "b", "c"])
        var buffer = ScreenBuffer(columns: 10, rows: 3)
        view.render(to: &buffer, in: Rect(x: 0, y: 0, width: 10, height: 3))

        #expect(buffer[0, 0].character == "a")
        #expect(buffer[1, 0].character == "b")
        #expect(buffer[2, 0].character == "c")
    }

    @Test func `buildLimitedAvailability returns the wrapped component`() {
        @ViewBuilder
        func make() -> some View {
            if #available(macOS 14, *) {
                Text("modern")
            } else {
                Text("legacy")
            }
        }

        var buffer = ScreenBuffer(columns: 10, rows: 1)
        make().render(to: &buffer, in: Rect(x: 0, y: 0, width: 10, height: 1))
        #expect(buffer[0, 0].character == "m")
    }
}

import Testing

@testable import KittySyntax
@testable import KittyWidgets
@testable import TerminalKitCodecs
@testable import TerminalKitRender

@Suite
struct LayoutTests {
    @Test
    func `VStack creation`() {
        let stack = VStack {
            Text("A")
            Text("B")
        }
        _ = stack
    }

    @Test
    func `HStack creation`() {
        let stack = HStack(spacing: 2) {
            Text("X")
        }
        _ = stack
    }
}

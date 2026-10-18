import Testing

@testable import KittySyntax
@testable import KittyWidgets
@testable import TerminalKitCodecs
@testable import TerminalKitRender

@Suite
struct ViewProtocolTests {
    @Test
    func `Text view creation`() {
        let text = Text("Hello", style: Style(bold: true))
        #expect(text.content == "Hello")
        #expect(text.style.bold)
    }

    @Test
    func `EmptyView creation`() {
        _ = EmptyView()
    }
}

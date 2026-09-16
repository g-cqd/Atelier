import Testing

@testable import KittyCodecs
@testable import KittyRenderer
@testable import KittySyntax
@testable import KittyWidgets

@Suite
struct ViewModifierTests {
    @Test
    func `ModifiedView preserves wrapped content`() {
        let inner = ModifiedView(content: Text("Hello"), modifier: BoldModifier())
        let outer = ModifiedView(content: inner, modifier: ItalicModifier())

        let resolvedInner = outer.modifierContent.resolve(as: ModifiedView<Text, BoldModifier>.self)
        let resolvedText = resolvedInner?.modifierContent.resolve(as: Text.self)

        #expect(resolvedInner != nil)
        #expect(resolvedText?.content == "Hello")
    }
}

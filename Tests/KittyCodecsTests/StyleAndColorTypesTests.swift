import Testing

@testable import KittyCodecs

@Suite
struct StyleAndColorTypesTests {
    @Test
    func `Default style equality`() {
        #expect(Style.default == Style())
    }

    @Test
    func `Color equality`() {
        #expect(Color.rgb(r: 255, g: 0, b: 0) == Color.rgb(r: 255, g: 0, b: 0))
        #expect(Color.indexed(1) != Color.indexed(2))
    }

    @Test
    func `KeyModifiers option set`() {
        var mods: KeyModifiers = [.shift, .ctrl]
        #expect(mods.contains(.shift))
        #expect(mods.contains(.ctrl))
        #expect(!mods.contains(.alt))
        mods.insert(.alt)
        #expect(mods.contains(.alt))
    }
}

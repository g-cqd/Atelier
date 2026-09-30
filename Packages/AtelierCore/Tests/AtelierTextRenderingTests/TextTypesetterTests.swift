import CoreGraphics
import Testing

@testable import AtelierTextRendering

@Suite
struct TextTypesetterTests {
    static let plainStyle = TextStyle(foreground: .fixed(RGBA(red: 0, green: 0, blue: 0)))
    static let font = FontSpec(pointSize: 12)

    @Test func `an unwrapped row lays out as one visual line`() async throws {
        let text = StyledText.plain(
            rows: ["let value = 1", "let other = 2"], font: Self.font, plainStyle: Self.plainStyle)
        let configuration = LayoutConfiguration(wrap: .none, lineHeight: 16)
        let geometry = try await TextTypesetter.layout(
            RowIndex(0) ..< RowIndex(2), of: text, configuration: configuration)
        #expect(geometry.count == 2)
        for row in geometry {
            #expect(row.lines.count == 1)
            #expect(row.height == 16)
            #expect(row.lines[0].carets.count > 1)
        }
    }

    @Test func `a wide row wraps into more than one visual line`() async throws {
        let text = StyledText.plain(
            rows: [String(repeating: "wide ", count: 40)], font: Self.font, plainStyle: Self.plainStyle)
        let configuration = LayoutConfiguration(wrap: .width(120), lineHeight: 16)
        let geometry = try await TextTypesetter.layout(
            RowIndex(0) ..< RowIndex(1), of: text, configuration: configuration)
        #expect(geometry[0].lines.count > 1)
        #expect(geometry[0].height == 16 * Float(geometry[0].lines.count))
    }

    @Test func `rendering produces an image sized to the rows and a row fill paints`() async throws {
        let text = StyledText.plain(rows: ["one", "two", "three"], font: Self.font, plainStyle: Self.plainStyle)
        let configuration = LayoutConfiguration(wrap: .none, lineHeight: 16)
        let layer = DecorationLayer(
            id: LayerID(0), zIndex: 0, paints: [RowIndex(1): [.rowFill(.fixed(RGBA(red: 1, green: 0, blue: 0)))]])
        let tile = try await TextTypesetter.render(
            RowIndex(0) ..< RowIndex(3), of: text, decorations: [layer], configuration: configuration,
            appearance: .light, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, scale: 2)
        #expect(tile.geometry.count == 3)
        #expect(tile.image.height == Int((16.0 * 3 * 2).rounded(.up)))
    }
}

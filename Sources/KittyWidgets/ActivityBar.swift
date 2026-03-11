import KittyCodecs
import KittyRenderer

public struct ActivityBar: Sendable {
    public struct Item: Sendable {
        public var icon: String
        public var id: String

        public init(icon: String, id: String) {
            self.icon = icon
            self.id = id
        }
    }

    public struct ActivityBarStyle: Sendable {
        public var normalStyle: Style
        public var activeStyle: Style

        public init(
            normalStyle: Style = Style(fg: .rgb(r: 0x8b, g: 0x94, b: 0x9e)),
            activeStyle: Style = Style(fg: .rgb(r: 0xf0, g: 0xf6, b: 0xfc), bold: true)
        ) {
            self.normalStyle = normalStyle
            self.activeStyle = activeStyle
        }
    }

    public var items: [Item]
    public var activeIndex: Int
    public var style: ActivityBarStyle

    public static let width = 3

    public init(
        items: [Item],
        activeIndex: Int = 0,
        style: ActivityBarStyle = .init()
    ) {
        self.items = items
        self.activeIndex = activeIndex
        self.style = style
    }

    public func render(to buffer: inout ScreenBuffer, in rect: Rect) {
        guard rect.width >= Self.width, rect.height > 0 else { return }

        let bgCell = Cell(character: " ", style: style.normalStyle)
        buffer.fill(row: rect.y, col: rect.x, width: Self.width, height: rect.height, cell: bgCell)

        for (i, item) in items.enumerated() {
            guard i < rect.height else { break }
            let row = rect.y + i
            let itemStyle = (i == activeIndex) ? style.activeStyle : style.normalStyle
            let icon = item.icon.first ?? " "
            // Center icon in the 3-column bar: [space][icon][space]
            buffer[row, rect.x + 1] = Cell(character: icon, style: itemStyle)
        }
    }

    /// Returns the item index for a click at the given row, or nil.
    public func itemIndex(atRow clickRow: Int, barY: Int) -> Int? {
        let relative = clickRow - barY
        guard relative >= 0, relative < items.count else { return nil }
        return relative
    }
}

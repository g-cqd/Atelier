import KittyCodecs
import KittyRenderer

public struct TabRibbon: Sendable {
    public struct Tab: Sendable {
        public var name: String
        public var isDirty: Bool

        public init(name: String, isDirty: Bool) {
            self.name = name
            self.isDirty = isDirty
        }
    }

    public struct TabRibbonStyle: Sendable {
        public var activeStyle: Style
        public var inactiveStyle: Style
        public var dirtyIndicator: String
        public var separator: String
        public var dirtyStyle: Style?

        public init(
            activeStyle: Style = Style(fg: .rgb(r: 0xf0, g: 0xf6, b: 0xfc), bold: true),
            inactiveStyle: Style = Style(fg: .rgb(r: 0x8b, g: 0x94, b: 0x9e)),
            dirtyIndicator: String = " \u{25CF}",
            separator: String = "\u{2502}",
            dirtyStyle: Style? = nil
        ) {
            self.activeStyle = activeStyle
            self.inactiveStyle = inactiveStyle
            self.dirtyIndicator = dirtyIndicator
            self.separator = separator
            self.dirtyStyle = dirtyStyle
        }
    }

    public var tabs: [Tab]
    public var activeIndex: Int
    public var scrollOffset: Int
    public var style: TabRibbonStyle

    public init(
        tabs: [Tab],
        activeIndex: Int,
        scrollOffset: Int = 0,
        style: TabRibbonStyle = .init()
    ) {
        self.tabs = tabs
        self.activeIndex = activeIndex
        self.scrollOffset = scrollOffset
        self.style = style
    }

    public func render(to buffer: inout ScreenBuffer, in rect: Rect) {
        guard rect.width > 0, rect.height > 0, !tabs.isEmpty else { return }

        // Fill background
        let bgCell = Cell(character: " ", style: style.inactiveStyle)
        buffer.fill(row: rect.y, col: rect.x, width: rect.width, height: 1, cell: bgCell)

        var col = rect.x
        let maxCol = rect.x + rect.width

        for i in scrollOffset..<tabs.count {
            guard col < maxCol else { break }
            let tab = tabs[i]
            let isActive = (i == activeIndex)
            let tabStyle = isActive ? style.activeStyle : style.inactiveStyle

            // Build tab label: " name ● │"
            var label = " \(tab.name)"
            if tab.isDirty {
                label += style.dirtyIndicator
            }
            label += " "

            // Write label
            for ch in label {
                guard col < maxCol else { break }
                buffer[rect.y, col] = Cell(character: ch, style: tabStyle)
                col += 1
            }

            // Write separator
            if col < maxCol {
                buffer[rect.y, col] = Cell(
                    character: Character(style.separator),
                    style: style.inactiveStyle
                )
                col += 1
            }
        }
    }

    /// Returns the tab index at a given column, or nil if outside all tabs.
    public func tabIndex(atColumn clickCol: Int, ribbonX: Int) -> Int? {
        guard !tabs.isEmpty else { return nil }

        var col = ribbonX
        for i in scrollOffset..<tabs.count {
            let tab = tabs[i]
            var label = " \(tab.name)"
            if tab.isDirty {
                label += style.dirtyIndicator
            }
            label += " "
            let tabWidth = label.count + 1 // +1 for separator

            if clickCol >= col && clickCol < col + tabWidth {
                return i
            }
            col += tabWidth
        }
        return nil
    }
}

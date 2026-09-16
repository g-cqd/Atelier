import AtelierText
public import KittyCodecs
public import KittyRenderer

public struct TabRibbon: View, Sendable {
    public struct Tab: Sendable {
        public var name: String
        public var isDirty: Bool
        public var isPreview: Bool
        public var statusIndicator: String?
        public var statusStyle: Style?

        public init(
            name: String,
            isDirty: Bool,
            isPreview: Bool = false,
            statusIndicator: String? = nil,
            statusStyle: Style? = nil
        ) {
            self.name = name
            self.isDirty = isDirty
            self.isPreview = isPreview
            self.statusIndicator = statusIndicator
            self.statusStyle = statusStyle
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

    public var body: Never { fatalError() }

    public func render(to buffer: inout ScreenBuffer, in rect: Rect) {
        guard rect.width > 0, rect.height > 0, !tabs.isEmpty else { return }

        // Fill background
        let bgCell = Cell(character: " ", style: style.inactiveStyle)
        buffer.fill(row: rect.y, col: rect.x, width: rect.width, height: 1, cell: bgCell)

        let maxCol = rect.x + rect.width
        let hasLeftOverflow = scrollOffset > 0
        let hasRightOverflow = tabsExtendBeyond(ribbonWidth: rect.width)

        var col = rect.x

        // Left overflow indicator
        if hasLeftOverflow {
            buffer[rect.y, col] = Cell(character: "<", style: style.inactiveStyle)
            col += 1
        }

        let rightBound = hasRightOverflow ? maxCol - 1 : maxCol

        for i in scrollOffset ..< tabs.count {
            guard col < rightBound else { break }
            let tab = tabs[i]
            let isActive = (i == activeIndex)
            var tabStyle = isActive ? style.activeStyle : style.inactiveStyle
            if tab.isPreview {
                tabStyle = Style(
                    fg: tabStyle.fg, bg: tabStyle.bg, bold: tabStyle.bold, italic: true)
            }

            col = renderLabelPrefix(
                for: tab, into: &buffer, row: rect.y, col: col, maxCol: rightBound,
                tabStyle: tabStyle)

            // Write separator
            if col < rightBound {
                buffer[rect.y, col] = Cell(
                    character: style.separator.first ?? "│",
                    style: style.inactiveStyle
                )
                col += 1
            }
        }

        // Right overflow indicator
        if hasRightOverflow {
            buffer[rect.y, maxCol - 1] = Cell(character: ">", style: style.inactiveStyle)
        }
    }

    /// Returns the tab index at a given column, or nil if outside all tabs.
    public func tabIndex(atColumn clickCol: Int, ribbonX: Int, ribbonWidth: Int) -> Int? {
        guard !tabs.isEmpty else { return nil }
        guard ribbonWidth > 0 else { return nil }

        let rightBound =
            ribbonX + ribbonWidth - (tabsExtendBeyond(ribbonWidth: ribbonWidth) ? 1 : 0)
        guard clickCol < rightBound else { return nil }

        var col = ribbonX
        if scrollOffset > 0 { col += 1 }  // skip left overflow indicator
        for i in scrollOffset ..< tabs.count {
            let tabWidth = tabLabelWidth(at: i)

            if clickCol >= col && clickCol < min(col + tabWidth, rightBound) {
                return i
            }
            col += tabWidth
            if col >= rightBound { break }
        }
        return nil
    }

    /// Compute tab label width for a given tab index.
    public func tabLabelWidth(at index: Int) -> Int {
        guard index >= 0, index < tabs.count else { return 0 }
        let tab = tabs[index]
        var label = " \(tab.name)"
        if let statusIndicator = tab.statusIndicator {
            label += " \(statusIndicator)"
        }
        if tab.isDirty {
            label += style.dirtyIndicator
        }
        label += " "
        return UnicodeWidth.displayWidth(of: label) + 1  // +1 for separator
    }

    /// Returns a clamped scrollOffset that ensures the given tab index is visible.
    public func clampedScrollOffset(activeIndex: Int, ribbonWidth: Int) -> Int {
        guard !tabs.isEmpty, ribbonWidth > 0 else { return 0 }
        let target = max(0, min(activeIndex, tabs.count - 1))

        var offset = scrollOffset

        // If active tab is before the scroll window, scroll left
        if target < offset {
            offset = target
        }

        // If active tab is past the visible area, scroll right.
        while offset < target {
            let reserveLeft = offset > 0 ? 1 : 0
            let reserveRight = target < tabs.count - 1 ? 1 : 0
            let availableWidth = max(0, ribbonWidth - reserveLeft - reserveRight)
            let requiredWidth = (offset ... target)
                .reduce(into: 0) { total, index in
                    total += tabLabelWidth(at: index)
                }
            if requiredWidth <= availableWidth {
                break
            }
            offset += 1
        }

        return max(0, min(offset, tabs.count - 1))
    }

    /// Whether tabs starting from scrollOffset extend beyond the given width.
    public func tabsExtendBeyond(ribbonWidth: Int) -> Bool {
        let availableWidth = max(0, ribbonWidth - (scrollOffset > 0 ? 1 : 0))
        var width = 0
        for i in scrollOffset ..< tabs.count {
            width += tabLabelWidth(at: i)
            if width > availableWidth { return true }
        }
        return false
    }

    private func renderLabelPrefix(
        for tab: Tab,
        into buffer: inout ScreenBuffer,
        row: Int,
        col: Int,
        maxCol: Int,
        tabStyle: Style
    ) -> Int {
        var currentCol = col

        currentCol = render(
            " \(tab.name)", style: tabStyle, into: &buffer, row: row, col: currentCol,
            maxCol: maxCol)

        if let statusIndicator = tab.statusIndicator {
            currentCol = render(
                " ", style: tabStyle, into: &buffer, row: row, col: currentCol, maxCol: maxCol)
            currentCol = render(
                statusIndicator,
                style: tab.statusStyle ?? tabStyle,
                into: &buffer,
                row: row,
                col: currentCol,
                maxCol: maxCol
            )
        }

        if tab.isDirty {
            currentCol = render(
                style.dirtyIndicator,
                style: style.dirtyStyle ?? tabStyle,
                into: &buffer,
                row: row,
                col: currentCol,
                maxCol: maxCol
            )
        }

        return render(
            " ", style: tabStyle, into: &buffer, row: row, col: currentCol, maxCol: maxCol)
    }

    private func render(
        _ text: String,
        style: Style,
        into buffer: inout ScreenBuffer,
        row: Int,
        col: Int,
        maxCol: Int
    ) -> Int {
        var currentCol = col
        for ch in text {
            let width = UnicodeWidth.displayWidth(of: ch)
            guard width > 0 else { continue }
            guard currentCol + width <= maxCol else { break }

            if width == 2 {
                buffer[row, currentCol] = Cell(character: ch, style: style, width: 2)
                buffer[row, currentCol + 1] = Cell(character: "\0", style: style, width: 0)
                currentCol += 2
            } else {
                buffer[row, currentCol] = Cell(character: ch, style: style)
                currentCol += 1
            }
        }
        return currentCol
    }
}

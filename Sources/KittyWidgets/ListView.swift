import KittyCodecs

public struct ListView: View, Sendable {
    public struct Item: Sendable {
        public var label: String
        public var icon: String
        public var suffix: String
        public var suffixStyle: Style
        public var isDirty: Bool

        public init(
            label: String,
            icon: String = "",
            suffix: String = "",
            suffixStyle: Style = .default,
            isDirty: Bool = false
        ) {
            self.label = label
            self.icon = icon
            self.suffix = suffix
            self.suffixStyle = suffixStyle
            self.isDirty = isDirty
        }
    }

    public struct ListViewStyle: Sendable {
        public var normalStyle: Style
        public var selectedStyle: Style
        public var dirtyIndicator: Character
        public var scrollIndicatorStyle: VerticalScrollIndicatorStyle

        public init(
            normalStyle: Style = .default,
            selectedStyle: Style = Style(bold: true),
            dirtyIndicator: Character = "\u{25CF}",
            scrollIndicatorStyle: VerticalScrollIndicatorStyle = VerticalScrollIndicatorStyle()
        ) {
            self.normalStyle = normalStyle
            self.selectedStyle = selectedStyle
            self.dirtyIndicator = dirtyIndicator
            self.scrollIndicatorStyle = scrollIndicatorStyle
        }
    }

    public var items: [Item]
    public var selectedIndex: Int
    public var scrollOffset: Int
    public var showsVerticalScrollIndicator: Bool
    public var style: ListViewStyle

    public init(
        items: [Item],
        selectedIndex: Int = 0,
        scrollOffset: Int = 0,
        showsVerticalScrollIndicator: Bool = true,
        style: ListViewStyle = ListViewStyle()
    ) {
        self.items = items
        self.selectedIndex = selectedIndex
        self.scrollOffset = scrollOffset
        self.showsVerticalScrollIndicator = showsVerticalScrollIndicator
        self.style = style
    }

    public var body: Never { fatalError() }
}

public import KittyCodecs

/// The look of `ScrollView`'s indicator; by default the track is blank, so only a dim gray thumb shows.
public struct ScrollViewStyle: Sendable, Equatable {
    public var trackStyle: Style
    public var thumbStyle: Style
    public var trackCharacter: Character
    public var thumbCharacter: Character

    public init(
        trackStyle: Style = .default,
        thumbStyle: Style = Style(fg: .rgb(r: 140, g: 140, b: 140), dim: true),
        trackCharacter: Character = " ",
        thumbCharacter: Character = "▓"
    ) {
        self.trackStyle = trackStyle
        self.thumbStyle = thumbStyle
        self.trackCharacter = trackCharacter
        self.thumbCharacter = thumbCharacter
    }

    /// Converts to the underlying indicator style used by the rendering layer.
    var indicatorStyle: VerticalScrollIndicatorStyle {
        VerticalScrollIndicatorStyle(
            trackStyle: trackStyle,
            thumbStyle: thumbStyle,
            trackCharacter: trackCharacter,
            thumbCharacter: thumbCharacter
        )
    }
}

/// A container that clips its content to the viewport and shows a vertical scroll indicator only when the content
/// overflows; the content renders its own visible slice from `scrollOffset`.
///
/// ```swift
/// ScrollView(contentHeight: lines.count, scrollOffset: offset) {
///     TextEditor(lines: lines, scrollOffset: offset, ...)
/// }
/// ```
public struct ScrollView<Content: View>: View, Sendable {
    public var content: Content
    public var contentHeight: Int
    public var scrollOffset: Int
    public var style: ScrollViewStyle

    public init(
        contentHeight: Int,
        scrollOffset: Int = 0,
        style: ScrollViewStyle = ScrollViewStyle(),
        @ViewBuilder content: () -> Content
    ) {
        self.contentHeight = max(0, contentHeight)
        self.scrollOffset = max(0, scrollOffset)
        self.style = style
        self.content = content()
    }

    public var body: Never { fatalError() }
}

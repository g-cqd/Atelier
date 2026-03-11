import KittyCodecs

/// Style configuration for ScrollView's scroll indicator.
///
/// Defaults to a translucent gray scrollbar that blends with background content.
/// The track is invisible (space character, default style) so only the thumb floats
/// over the content, similar to modern overlay scrollbars.
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

/// A generic scrollable container that clips content to a viewport and displays
/// a vertical scroll indicator when content overflows.
///
/// The scrollbar is automatically hidden when content fits within the viewport.
/// Content is responsible for rendering the visible slice based on `scrollOffset`.
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

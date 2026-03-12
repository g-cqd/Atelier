import KittyCodecs

public struct ScrollMetrics: Sendable, Equatable {
    public var contentLength: Int
    public var viewportLength: Int
    public var offset: Int
    public var maxOffset: Int

    public init(
        contentLength: Int,
        viewportLength: Int,
        offset: Int,
        maxOffset: Int? = nil
    ) {
        let resolvedContentLength = max(0, contentLength)
        let resolvedViewportLength = max(0, viewportLength)
        let naturalMaxOffset = max(0, resolvedContentLength - resolvedViewportLength)
        let resolvedMaxOffset = max(naturalMaxOffset, maxOffset ?? naturalMaxOffset)

        self.contentLength = resolvedContentLength
        self.viewportLength = resolvedViewportLength
        self.maxOffset = resolvedMaxOffset
        self.offset = min(max(0, offset), resolvedMaxOffset)
    }

    public var isScrollable: Bool {
        viewportLength > 0 && maxOffset > 0
    }
}

public struct VerticalScrollIndicatorStyle: Sendable, Equatable {
    public var trackStyle: Style
    public var thumbStyle: Style
    public var trackCharacter: Character
    public var thumbCharacter: Character

    public init(
        trackStyle: Style = .default,
        thumbStyle: Style = .default,
        trackCharacter: Character = "│",
        thumbCharacter: Character = "█"
    ) {
        self.trackStyle = trackStyle
        self.thumbStyle = thumbStyle
        self.trackCharacter = trackCharacter
        self.thumbCharacter = thumbCharacter
    }
}

public struct VerticalScrollIndicator: View, Sendable {
    public var metrics: ScrollMetrics
    public var style: VerticalScrollIndicatorStyle

    public init(
        metrics: ScrollMetrics,
        style: VerticalScrollIndicatorStyle = VerticalScrollIndicatorStyle()
    ) {
        self.metrics = metrics
        self.style = style
    }

    public var body: Never { fatalError() }
}

public enum VerticalScrollIndicatorLayout {
    public static func thumbRect(for metrics: ScrollMetrics, in rect: Rect) -> Rect? {
        guard !rect.isEmpty else { return nil }

        let thumbHeight = thumbLength(for: metrics, trackHeight: rect.height)
        let maxThumbOrigin = max(0, rect.height - thumbHeight)
        let thumbOrigin: Int

        if maxThumbOrigin == 0 || metrics.maxOffset == 0 {
            thumbOrigin = 0
        } else {
            let progress = Double(metrics.offset) / Double(metrics.maxOffset)
            thumbOrigin = min(
                maxThumbOrigin,
                max(0, Int((progress * Double(maxThumbOrigin)).rounded()))
            )
        }

        return Rect(
            x: rect.x,
            y: rect.y + thumbOrigin,
            width: rect.width,
            height: thumbHeight
        )
    }

    public static func gripOffset(
        for metrics: ScrollMetrics,
        in rect: Rect,
        pointerRow: Int
    ) -> Int? {
        guard pointerRow >= rect.y && pointerRow < rect.maxY else { return nil }
        guard let thumbRect = thumbRect(for: metrics, in: rect) else { return nil }

        if pointerRow >= thumbRect.y && pointerRow < thumbRect.maxY {
            return pointerRow - thumbRect.y
        }

        return max(0, min(thumbRect.height - 1, thumbRect.height / 2))
    }

    public static func offset(
        for metrics: ScrollMetrics,
        in rect: Rect,
        pointerRow: Int,
        gripOffset: Int
    ) -> Int {
        guard let thumbRect = thumbRect(for: metrics, in: rect) else { return 0 }
        guard metrics.maxOffset > 0 else { return 0 }

        let maxThumbOrigin = max(0, rect.height - thumbRect.height)
        guard maxThumbOrigin > 0 else { return 0 }

        let resolvedGripOffset = max(0, min(gripOffset, thumbRect.height - 1))
        let targetThumbOrigin = max(
            0,
            min(pointerRow - rect.y - resolvedGripOffset, maxThumbOrigin)
        )
        let progress = Double(targetThumbOrigin) / Double(maxThumbOrigin)
        return min(
            metrics.maxOffset,
            max(0, Int((progress * Double(metrics.maxOffset)).rounded()))
        )
    }

    private static func thumbLength(for metrics: ScrollMetrics, trackHeight: Int) -> Int {
        guard trackHeight > 0 else { return 0 }
        guard metrics.isScrollable else { return trackHeight }

        let totalLength = max(1, max(metrics.contentLength, metrics.viewportLength))
        let proportionalLength =
            (trackHeight * max(1, metrics.viewportLength) + totalLength - 1) / totalLength
        return min(trackHeight, max(1, proportionalLength))
    }
}

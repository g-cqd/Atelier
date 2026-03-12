import KittyCodecs
import KittyRenderer

public struct HorizontalScrollIndicatorStyle: Sendable, Equatable {
    public var trackStyle: Style
    public var thumbStyle: Style
    public var trackCharacter: Character
    public var thumbCharacter: Character

    public init(
        trackStyle: Style = .default,
        thumbStyle: Style = .default,
        trackCharacter: Character = " ",
        thumbCharacter: Character = "\u{2501}"
    ) {
        self.trackStyle = trackStyle
        self.thumbStyle = thumbStyle
        self.trackCharacter = trackCharacter
        self.thumbCharacter = thumbCharacter
    }
}

public struct HorizontalScrollIndicator: View, Sendable {
    public var metrics: ScrollMetrics
    public var style: HorizontalScrollIndicatorStyle

    public init(
        metrics: ScrollMetrics,
        style: HorizontalScrollIndicatorStyle = HorizontalScrollIndicatorStyle()
    ) {
        self.metrics = metrics
        self.style = style
    }

    public var body: Never { fatalError() }
}

public enum HorizontalScrollIndicatorLayout {
    public static func thumbRect(for metrics: ScrollMetrics, in rect: Rect) -> Rect? {
        guard !rect.isEmpty else { return nil }

        let thumbWidth = thumbLength(for: metrics, trackWidth: rect.width)
        let maxThumbOrigin = max(0, rect.width - thumbWidth)
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
            x: rect.x + thumbOrigin,
            y: rect.y,
            width: thumbWidth,
            height: rect.height
        )
    }

    public static func gripOffset(
        for metrics: ScrollMetrics,
        in rect: Rect,
        pointerCol: Int
    ) -> Int? {
        guard pointerCol >= rect.x && pointerCol < rect.maxX else { return nil }
        guard let thumbRect = thumbRect(for: metrics, in: rect) else { return nil }

        if pointerCol >= thumbRect.x && pointerCol < thumbRect.maxX {
            return pointerCol - thumbRect.x
        }

        return max(0, min(thumbRect.width - 1, thumbRect.width / 2))
    }

    public static func offset(
        for metrics: ScrollMetrics,
        in rect: Rect,
        pointerCol: Int,
        gripOffset: Int
    ) -> Int {
        guard let thumbRect = thumbRect(for: metrics, in: rect) else { return 0 }
        guard metrics.maxOffset > 0 else { return 0 }

        let maxThumbOrigin = max(0, rect.width - thumbRect.width)
        guard maxThumbOrigin > 0 else { return 0 }

        let resolvedGripOffset = max(0, min(gripOffset, thumbRect.width - 1))
        let targetThumbOrigin = max(
            0,
            min(pointerCol - rect.x - resolvedGripOffset, maxThumbOrigin)
        )
        let progress = Double(targetThumbOrigin) / Double(maxThumbOrigin)
        return min(
            metrics.maxOffset,
            max(0, Int((progress * Double(metrics.maxOffset)).rounded()))
        )
    }

    private static func thumbLength(for metrics: ScrollMetrics, trackWidth: Int) -> Int {
        guard trackWidth > 0 else { return 0 }
        guard metrics.isScrollable else { return trackWidth }

        let totalLength = max(1, max(metrics.contentLength, metrics.viewportLength))
        let proportionalLength =
            (trackWidth * max(1, metrics.viewportLength) + totalLength - 1) / totalLength
        return min(trackWidth, max(1, proportionalLength))
    }
}

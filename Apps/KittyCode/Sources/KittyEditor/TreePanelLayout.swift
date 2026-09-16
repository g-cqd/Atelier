public import KittyWidgets

public enum TreePanelLayout {
    public static func verticalScrollMetrics(
        rowCount: Int,
        scrollOffset: Int,
        in rect: Rect
    ) -> ScrollMetrics {
        ScrollMetrics(
            contentLength: rowCount,
            viewportLength: rect.height,
            offset: scrollOffset,
            maxOffset: max(0, rowCount - 1)
        )
    }

    public static func contentWidth(rowCount: Int, in rect: Rect) -> Int {
        max(0, rect.width - (showsVerticalScrollIndicator(rowCount: rowCount, in: rect) ? 1 : 0))
    }

    public static func verticalScrollIndicatorRect(rowCount: Int, in rect: Rect) -> Rect? {
        guard showsVerticalScrollIndicator(rowCount: rowCount, in: rect) else { return nil }
        return Rect(x: rect.maxX - 1, y: rect.y, width: 1, height: rect.height)
    }

    public static func scrollGripOffset(
        rowCount: Int,
        scrollOffset: Int,
        in rect: Rect,
        pointerRow: Int
    ) -> Int? {
        guard let indicatorRect = verticalScrollIndicatorRect(rowCount: rowCount, in: rect) else {
            return nil
        }

        return VerticalScrollIndicatorLayout.gripOffset(
            for: verticalScrollMetrics(rowCount: rowCount, scrollOffset: scrollOffset, in: rect),
            in: indicatorRect,
            pointerRow: pointerRow
        )
    }

    public static func scrollOffset(
        rowCount: Int,
        currentOffset: Int,
        in rect: Rect,
        pointerRow: Int,
        gripOffset: Int
    ) -> Int {
        guard let indicatorRect = verticalScrollIndicatorRect(rowCount: rowCount, in: rect) else {
            return currentOffset
        }

        return VerticalScrollIndicatorLayout.offset(
            for: verticalScrollMetrics(rowCount: rowCount, scrollOffset: currentOffset, in: rect),
            in: indicatorRect,
            pointerRow: pointerRow,
            gripOffset: gripOffset
        )
    }

    private static func showsVerticalScrollIndicator(rowCount: Int, in rect: Rect) -> Bool {
        rect.width > 0 && rect.height > 0 && rowCount > rect.height
    }
}

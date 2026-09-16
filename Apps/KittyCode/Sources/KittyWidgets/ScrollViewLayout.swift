/// Layout calculations for `ScrollView` rendering, hit testing, and drag handling.
///
/// Follows the same pattern as `TreeViewLayout` and `TextEditorLayout`:
/// widget-specific metrics on top, delegating to `VerticalScrollIndicatorLayout`
/// for universal proportional math.
public enum ScrollViewLayout {
    /// Scroll metrics for the scroll view.
    public static func verticalScrollMetrics<Content>(
        for scrollView: ScrollView<Content>,
        in rect: Rect
    ) -> ScrollMetrics {
        ScrollMetrics(
            contentLength: scrollView.contentHeight,
            viewportLength: rect.height,
            offset: scrollView.scrollOffset
        )
    }

    /// Width reserved for the scroll indicator (0 if content fits).
    public static func scrollIndicatorWidth<Content>(
        for scrollView: ScrollView<Content>,
        in rect: Rect
    ) -> Int {
        let metrics = verticalScrollMetrics(for: scrollView, in: rect)
        return metrics.isScrollable && rect.width > 0 ? 1 : 0
    }

    /// Available width for content (total width minus indicator when scrollable).
    public static func contentWidth<Content>(
        for scrollView: ScrollView<Content>,
        in rect: Rect
    ) -> Int {
        max(0, rect.width - scrollIndicatorWidth(for: scrollView, in: rect))
    }

    /// The rect allocated to the content area (excludes scrollbar).
    public static func contentRect<Content>(
        for scrollView: ScrollView<Content>,
        in rect: Rect
    ) -> Rect {
        let width = contentWidth(for: scrollView, in: rect)
        return Rect(x: rect.x, y: rect.y, width: width, height: rect.height)
    }

    /// The rect for the scroll indicator column, or nil if content fits.
    public static func verticalScrollIndicatorRect<Content>(
        for scrollView: ScrollView<Content>,
        in rect: Rect
    ) -> Rect? {
        guard scrollIndicatorWidth(for: scrollView, in: rect) > 0 else { return nil }
        return Rect(x: rect.maxX - 1, y: rect.y, width: 1, height: rect.height)
    }

    /// Returns the grip offset when the pointer is on the thumb, for initiating drag.
    public static func scrollGripOffset<Content>(
        for scrollView: ScrollView<Content>,
        in rect: Rect,
        pointerRow: Int
    ) -> Int? {
        guard let indicatorRect = verticalScrollIndicatorRect(for: scrollView, in: rect) else {
            return nil
        }
        return VerticalScrollIndicatorLayout.gripOffset(
            for: verticalScrollMetrics(for: scrollView, in: rect),
            in: indicatorRect,
            pointerRow: pointerRow
        )
    }

    /// Calculates the content scroll offset from a pointer position during drag.
    public static func scrollOffset<Content>(
        for scrollView: ScrollView<Content>,
        in rect: Rect,
        pointerRow: Int,
        gripOffset: Int
    ) -> Int {
        guard let indicatorRect = verticalScrollIndicatorRect(for: scrollView, in: rect) else {
            return scrollView.scrollOffset
        }
        return VerticalScrollIndicatorLayout.offset(
            for: verticalScrollMetrics(for: scrollView, in: rect),
            in: indicatorRect,
            pointerRow: pointerRow,
            gripOffset: gripOffset
        )
    }

    /// Clamp a scroll offset to valid range for the given scroll view in the given rect.
    public static func clampedOffset<Content>(
        for scrollView: ScrollView<Content>,
        in rect: Rect,
        offset: Int
    ) -> Int {
        let metrics = verticalScrollMetrics(for: scrollView, in: rect)
        return min(max(0, offset), metrics.maxOffset)
    }
}

public enum TreeViewLayout {
    public static func contentWidth<Value>(for tree: TreeView<Value>, in rect: Rect) -> Int {
        max(0, rect.width - verticalScrollIndicatorWidth(for: tree, in: rect))
    }

    public static func verticalScrollMetrics<Value>(for tree: TreeView<Value>, in rect: Rect)
        -> ScrollMetrics
    {
        let rowCount = tree.visibleRows().count
        return ScrollMetrics(
            contentLength: rowCount,
            viewportLength: rect.height,
            offset: tree.scrollOffset,
            maxOffset: max(0, rowCount - 1)
        )
    }

    public static func verticalScrollIndicatorRect<Value>(
        for tree: TreeView<Value>,
        in rect: Rect
    ) -> Rect? {
        guard verticalScrollIndicatorWidth(for: tree, in: rect) > 0 else { return nil }
        return Rect(x: rect.maxX - 1, y: rect.y, width: 1, height: rect.height)
    }

    public static func scrollGripOffset<Value>(
        for tree: TreeView<Value>,
        in rect: Rect,
        pointerRow: Int
    ) -> Int? {
        guard let indicatorRect = verticalScrollIndicatorRect(for: tree, in: rect) else {
            return nil
        }
        return VerticalScrollIndicatorLayout.gripOffset(
            for: verticalScrollMetrics(for: tree, in: rect),
            in: indicatorRect,
            pointerRow: pointerRow
        )
    }

    public static func scrollOffset<Value>(
        for tree: TreeView<Value>,
        in rect: Rect,
        pointerRow: Int,
        gripOffset: Int
    ) -> Int {
        guard let indicatorRect = verticalScrollIndicatorRect(for: tree, in: rect) else {
            return tree.scrollOffset
        }

        return VerticalScrollIndicatorLayout.offset(
            for: verticalScrollMetrics(for: tree, in: rect),
            in: indicatorRect,
            pointerRow: pointerRow,
            gripOffset: gripOffset
        )
    }

    private static func verticalScrollIndicatorWidth<Value>(
        for tree: TreeView<Value>,
        in rect: Rect
    ) -> Int {
        guard tree.showsVerticalScrollIndicator, rect.width > 0, rect.height > 0 else { return 0 }
        return tree.visibleRows().count > rect.height ? 1 : 0
    }
}

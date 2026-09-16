public import KittyCodecs
public import KittyRenderer

public struct OverlayBoxStyle {
    public var borderStyle: Style
    public var fillStyle: Style
    public var bodyStyle: Style

    public init(borderStyle: Style, fillStyle: Style, bodyStyle: Style) {
        self.borderStyle = borderStyle
        self.fillStyle = fillStyle
        self.bodyStyle = bodyStyle
    }
}

public struct OverlayBoxLayout: Sendable, Equatable {
    public let boxRect: Rect
    public let titleRow: Int
    public let subtitleRow: Int?
    public let contentRect: Rect

    public init(boxRect: Rect, titleRow: Int, subtitleRow: Int?, contentRect: Rect) {
        self.boxRect = boxRect
        self.titleRow = titleRow
        self.subtitleRow = subtitleRow
        self.contentRect = contentRect
    }
}

public enum OverlayBox {
    public static func layout(
        title: String,
        subtitle: String?,
        width: Int,
        height: Int,
        columns: Int,
        rows: Int
    ) -> OverlayBoxLayout {
        let boxWidth = min(max(12, width), max(12, columns - 2))
        let boxHeight = min(max(5, height), max(5, rows - 2))
        let boxX = max(0, (columns - boxWidth) / 2)
        let boxY = max(0, (rows - boxHeight) / 2)
        let titleRow = boxY + 1
        let subtitleRow = subtitle == nil ? nil : titleRow + 1
        let contentStartY = boxY + (subtitle == nil ? 2 : 3)
        let contentHeight = max(1, boxHeight - (subtitle == nil ? 3 : 4))

        return OverlayBoxLayout(
            boxRect: Rect(x: boxX, y: boxY, width: boxWidth, height: boxHeight),
            titleRow: titleRow,
            subtitleRow: subtitleRow,
            contentRect: Rect(
                x: boxX + 2, y: contentStartY, width: max(1, boxWidth - 4), height: contentHeight)
        )
    }

    public static func draw(
        into buffer: inout ScreenBuffer,
        layout: OverlayBoxLayout,
        title: String,
        style: OverlayBoxStyle
    ) {
        let rect = layout.boxRect

        buffer.fill(
            row: rect.y,
            col: rect.x,
            width: rect.width,
            height: rect.height,
            cell: Cell(character: " ", style: style.fillStyle)
        )

        guard rect.width >= 2, rect.height >= 2 else { return }

        buffer[rect.y, rect.x] = Cell(character: "┌", style: style.borderStyle)
        buffer[rect.y, rect.maxX - 1] = Cell(character: "┐", style: style.borderStyle)
        buffer[rect.maxY - 1, rect.x] = Cell(character: "└", style: style.borderStyle)
        buffer[rect.maxY - 1, rect.maxX - 1] = Cell(character: "┘", style: style.borderStyle)

        for col in (rect.x + 1)..<(rect.maxX - 1) {
            buffer[rect.y, col] = Cell(character: "─", style: style.borderStyle)
            buffer[rect.maxY - 1, col] = Cell(character: "─", style: style.borderStyle)
        }

        for row in (rect.y + 1)..<(rect.maxY - 1) {
            buffer[row, rect.x] = Cell(character: "│", style: style.borderStyle)
            buffer[row, rect.maxX - 1] = Cell(character: "│", style: style.borderStyle)
        }

        let titleText = String(title.prefix(max(0, rect.width - 4)))
        buffer.write(titleText, row: layout.titleRow, col: rect.x + 2, style: style.bodyStyle)
    }
}

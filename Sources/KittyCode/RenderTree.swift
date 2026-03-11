import KittyCodecs
import KittyFileTree
import KittyRenderer
import KittySymbols
import KittyText
import KittyWidgets

@MainActor
func renderTreePanel(
    pipeline: RenderPipeline,
    state: EditorState,
    treeRect: Rect,
    colorScheme: EditorState.ColorScheme
) {
    guard treeRect.width > 0, treeRect.height > 0 else { return }

    let rows = state.cachedFlatTree
    let rowCount = rows.count
    let provider = state.fileStatusProvider
    let normalStyle = colorScheme.treeBg
    let selectedStyle = colorScheme.treeSelected
    let contentWidth = TreePanelLayout.contentWidth(rowCount: rowCount, in: treeRect)
    let metrics = TreePanelLayout.verticalScrollMetrics(
        rowCount: rowCount,
        scrollOffset: state.treeScrollOffset,
        in: treeRect
    )
    let start = max(0, min(metrics.offset, rowCount))
    let visibleCount = min(treeRect.height, rowCount - start)

    for offset in 0..<visibleCount {
        let rowIndex = start + offset
        let entry = rows[rowIndex]
        let node = entry.node
        let rowStyle = rowIndex == state.selectedTreeIndex
            ? selectedStyle
            : (node.isDirectory ? colorScheme.treeDir : normalStyle)
        let screenRow = treeRect.y + offset

        pipeline.buffer.fill(
            row: screenRow,
            col: treeRect.x,
            width: treeRect.width,
            height: 1,
            cell: Cell(character: " ", style: rowStyle)
        )

        let icon = treeRowIcon(for: node, symbolTheme: state.symbolTheme)
        let label = String(repeating: " ", count: entry.depth * 2) + icon + node.name
        let visibleLabel = String(label.prefix(contentWidth))
        pipeline.buffer.write(visibleLabel, row: screenRow, col: treeRect.x, style: rowStyle)

        guard let status = provider?.status(for: node.path), !status.indicator.isEmpty else {
            continue
        }

        let suffixText = " " + status.indicator
        let suffixWidth = UnicodeWidth.displayWidth(of: suffixText)
        let suffixCol = treeRect.x + contentWidth - suffixWidth
        let labelWidth = UnicodeWidth.displayWidth(of: visibleLabel)

        if suffixCol > treeRect.x + labelWidth {
            pipeline.buffer.write(
                suffixText,
                row: screenRow,
                col: suffixCol,
                style: colorScheme.gitStatusStyle(for: status.statusColor)
            )
        }
    }

    if visibleCount < treeRect.height {
        let emptyCell = Cell(character: " ", style: normalStyle)
        for offset in visibleCount..<treeRect.height {
            pipeline.buffer.fill(
                row: treeRect.y + offset,
                col: treeRect.x,
                width: treeRect.width,
                height: 1,
                cell: emptyCell
            )
        }
    }

    if let indicatorRect = TreePanelLayout.verticalScrollIndicatorRect(rowCount: rowCount, in: treeRect) {
        VerticalScrollIndicator(
            metrics: metrics,
            style: colorScheme.verticalScrollIndicator
        ).render(to: &pipeline.buffer, in: indicatorRect)
    }
}

private func treeRowIcon(for node: FileNode, symbolTheme: TerminalSymbolTheme) -> String {
    if node.isDirectory {
        return node.isExpanded ? symbolTheme[.folderOpen].text + " " : symbolTheme[.folderClosed].text + " "
    }

    return symbolTheme[.file].text + " "
}

import KittyCodecs
import KittyRenderer
import KittySymbols
import KittyWidgets

@MainActor
func renderOpenFilesPanel(
    pipeline: RenderPipeline,
    state: EditorState,
    rect: Rect,
    colorScheme: EditorState.ColorScheme
) {
    guard rect.width > 0, rect.height > 0 else { return }

    let buffers = state.bufferManager.buffers
    guard !buffers.isEmpty else {
        let emptyCell = Cell(character: " ", style: colorScheme.treeBg)
        pipeline.buffer.fill(row: rect.y, col: rect.x, width: rect.width, height: rect.height, cell: emptyCell)
        return
    }

    let activeIdx = state.bufferManager.activeIndex
    let scrollOffset = state.openFilesScrollOffset

    let normalStyle: Style
    if let fg = state.config.theme.openFilesForeground {
        normalStyle = Style(fg: fg.color)
    } else {
        normalStyle = colorScheme.treeBg
    }

    let selectedStyle: Style
    if let fg = state.config.theme.openFilesSelectedForeground {
        selectedStyle = Style(fg: fg.color, bold: true)
    } else {
        selectedStyle = colorScheme.treeSelected
    }

    for row in 0..<rect.height {
        let bufferIdx = scrollOffset + row
        let screenRow = rect.y + row

        if bufferIdx < buffers.count {
            let buffer = buffers[bufferIdx]
            let isActive = (bufferIdx == activeIdx)
            let rowStyle = isActive ? selectedStyle : normalStyle
            let status = state.config.showGitStatus && state.config.gitDecorations.showOpenFilesStatus
                ? state.fileStatusProvider?.status(for: buffer.filePath)
                : nil
            let statusIndicator = status?.indicator.isEmpty == false ? status?.indicator : nil

            let icon = state.symbolTheme[.file].text
            let prefix = icon.isEmpty ? " " : " \(icon) "
            var label = prefix + buffer.fileName
            if let statusIndicator {
                label += " \(statusIndicator)"
            }
            if buffer.isDirty {
                label += " \u{25CF}"
            }
            let padded = String(label.prefix(rect.width)).padding(toLength: rect.width, withPad: " ", startingAt: 0)

            pipeline.buffer.write(padded, row: screenRow, col: rect.x, style: rowStyle)
            if let status,
               let statusIndicator,
               let indicatorRange = padded.range(of: " \(statusIndicator)") {
                let indicatorCol = padded.distance(from: padded.startIndex, to: indicatorRange.lowerBound) + 1
                pipeline.buffer.write(
                    statusIndicator,
                    row: screenRow,
                    col: rect.x + indicatorCol,
                    style: colorScheme.gitStatusStyle(for: status.statusColor)
                )
            }
        } else {
            let emptyCell = Cell(character: " ", style: normalStyle)
            pipeline.buffer.fill(row: screenRow, col: rect.x, width: rect.width, height: 1, cell: emptyCell)
        }
    }
}

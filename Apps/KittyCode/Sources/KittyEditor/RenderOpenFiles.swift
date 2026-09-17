import AtelierGit
import AtelierText
import KittyCodecs
import KittyFileTree
public import KittyRenderer
import KittySymbols
public import KittyWidgets
import KittyWorkspace

@MainActor
public func renderOpenFilesPanel(
    pipeline: RenderPipeline,
    state: EditorState,
    rect: Rect,
    colorScheme: EditorState.ColorScheme
) {
    guard rect.width > 0, rect.height > 0 else { return }

    let buffers = state.bufferManager.buffers
    guard !buffers.isEmpty else {
        let emptyCell = Cell(character: " ", style: colorScheme.treeBg)
        pipeline.buffer.fill(
            row: rect.y, col: rect.x, width: rect.width, height: rect.height, cell: emptyCell)
        return
    }

    let theme = state.config.theme
    let normalStyle = theme.resolvedStyle(theme.openFilesForeground) ?? colorScheme.treeBg
    let selectedStyle =
        theme.resolvedStyle(theme.openFilesSelectedForeground, bold: true)
        ?? colorScheme.treeSelected
    let icon = state.symbolTheme[.file].text

    let items: [ListView.Item] = buffers.map { buffer in
        let status =
            state.config.git.enabled && state.config.git.decorations.showOpenFilesStatus
            ? state.fileStatusProvider?.status(for: buffer.filePath)
            : nil
        let statusIndicator = status?.indicator.isEmpty == false ? status?.indicator : nil
        let suffixStyle = status.map { colorScheme.gitStatusStyle(for: $0.statusColor) } ?? .default
        return ListView.Item(
            label: buffer.fileName,
            icon: icon,
            suffix: statusIndicator ?? "",
            suffixStyle: suffixStyle,
            isDirty: buffer.isDirty
        )
    }

    let list = ListView(
        items: items,
        selectedIndex: state.bufferManager.activeIndex,
        scrollOffset: state.openFilesScrollOffset,
        showsVerticalScrollIndicator: buffers.count > rect.height,
        style: ListView.ListViewStyle(
            normalStyle: normalStyle,
            selectedStyle: selectedStyle,
            scrollIndicatorStyle: colorScheme.verticalScrollIndicator
        )
    )
    list.render(to: &pipeline.buffer, in: rect)
}

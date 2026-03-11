import KittyCodecs
import KittyRenderer
import KittyWidgets

@MainActor
func renderOverlay(
    pipeline: RenderPipeline,
    state: EditorState,
    columns: Int,
    rows: Int,
    colorScheme: EditorState.ColorScheme
) -> (row: Int, col: Int)? {
    if let prompt = state.prompt {
        return renderPromptOverlay(
            prompt,
            into: &pipeline.buffer,
            columns: columns,
            rows: rows,
            colorScheme: colorScheme
        )
    }

    if let contextMenu = state.contextMenu {
        renderContextMenuOverlay(
            contextMenu,
            into: &pipeline.buffer,
            columns: columns,
            rows: rows,
            colorScheme: colorScheme
        )
    }

    return nil
}

@MainActor
func contextMenuItemIndex(
    at mouse: MouseEvent,
    state: EditorState,
    columns: Int,
    rows: Int
) -> Int? {
    guard let contextMenu = state.contextMenu else { return nil }
    let layout = contextMenuOverlayLayout(for: contextMenu, columns: columns, rows: rows)
    let row = mouse.row - 1
    let col = mouse.col - 1

    guard row >= layout.contentRect.y, row < layout.contentRect.maxY else { return nil }
    guard col >= layout.contentRect.x, col < layout.contentRect.maxX else { return nil }

    let itemIndex = row - layout.contentRect.y
    guard itemIndex >= 0, itemIndex < contextMenu.items.count else { return nil }
    return itemIndex
}

@MainActor
func isWithinContextMenu(
    _ mouse: MouseEvent,
    state: EditorState,
    columns: Int,
    rows: Int
) -> Bool {
    guard let contextMenu = state.contextMenu else { return false }
    let layout = contextMenuOverlayLayout(for: contextMenu, columns: columns, rows: rows)
    let row = mouse.row - 1
    let col = mouse.col - 1
    return row >= layout.boxRect.y && row < layout.boxRect.maxY && col >= layout.boxRect.x && col < layout.boxRect.maxX
}

private func overlayBoxStyle(from colorScheme: EditorState.ColorScheme) -> OverlayBoxStyle {
    OverlayBoxStyle(
        borderStyle: colorScheme.titleBar,
        fillStyle: colorScheme.statusBar,
        bodyStyle: colorScheme.editorText
    )
}

private func renderPromptOverlay(
    _ prompt: EditorPrompt,
    into buffer: inout ScreenBuffer,
    columns: Int,
    rows: Int,
    colorScheme: EditorState.ColorScheme
) -> (row: Int, col: Int) {
    let promptLine = prompt.promptText + prompt.input
    let messageLine = prompt.message ?? "Enter a destination path."
    let width = min(max(max(promptLine.count, messageLine.count) + 6, 34), max(20, columns - 4))
    let height = 6
    let layout = OverlayBox.layout(
        title: "Save File",
        subtitle: messageLine,
        width: width,
        height: height,
        columns: columns,
        rows: rows
    )

    OverlayBox.draw(
        into: &buffer,
        layout: layout,
        title: "Save File",
        style: overlayBoxStyle(from: colorScheme)
    )
    if let subtitleRow = layout.subtitleRow {
        buffer.write(
            String(messageLine.prefix(layout.contentRect.width)),
            row: subtitleRow,
            col: layout.contentRect.x,
            style: colorScheme.lineNumber
        )
    }

    let inputRow = layout.contentRect.maxY - 1
    let inputCol = layout.contentRect.x
    let inputStyle = prompt.message == nil ? colorScheme.editorText : colorScheme.gitDeleted
    let renderedPrompt = String(promptLine.prefix(layout.contentRect.width))
    buffer.write(renderedPrompt, row: inputRow, col: inputCol, style: inputStyle)

    let cursorCol = min(layout.contentRect.maxX - 1, inputCol + min(promptLine.count, layout.contentRect.width - 1))
    return (row: inputRow, col: cursorCol)
}

private func renderContextMenuOverlay(
    _ contextMenu: EditorState.ContextMenuState,
    into buffer: inout ScreenBuffer,
    columns: Int,
    rows: Int,
    colorScheme: EditorState.ColorScheme
) {
    let layout = contextMenuOverlayLayout(for: contextMenu, columns: columns, rows: rows)
    OverlayBox.draw(
        into: &buffer,
        layout: layout,
        title: contextMenu.title,
        style: overlayBoxStyle(from: colorScheme)
    )
    if let subtitle = contextMenu.subtitle, let subtitleRow = layout.subtitleRow {
        buffer.write(
            String(subtitle.prefix(layout.contentRect.width)),
            row: subtitleRow,
            col: layout.contentRect.x,
            style: colorScheme.lineNumber
        )
    }

    let items = contextMenu.items.map { item in
        ListView.Item(
            label: item.title,
            suffix: item.shortcut,
            suffixStyle: colorScheme.lineNumber
        )
    }
    let listStyle = ListView.ListViewStyle(
        normalStyle: colorScheme.editorText,
        selectedStyle: colorScheme.treeSelected,
        dirtyIndicator: " ",
        scrollIndicatorStyle: colorScheme.verticalScrollIndicator
    )
    ListView(
        items: items,
        selectedIndex: contextMenu.selectedIndex,
        scrollOffset: 0,
        showsVerticalScrollIndicator: false,
        style: listStyle
    ).render(to: &buffer, in: layout.contentRect)
}

private func contextMenuOverlayLayout(
    for contextMenu: EditorState.ContextMenuState,
    columns: Int,
    rows: Int
) -> OverlayBoxLayout {
    let widestItem = contextMenu.items.reduce(0) { partial, item in
        max(partial, item.title.count + (item.shortcut.isEmpty ? 0 : item.shortcut.count + 1))
    }
    let preferredWidth = min(max(max(contextMenu.title.count, widestItem) + 8, 28), max(20, columns - 4))
    let subtitleRows = contextMenu.subtitle == nil ? 0 : 1
    let preferredHeight = min(max(contextMenu.items.count + subtitleRows + 4, 6), max(6, rows - 4))
    return OverlayBox.layout(
        title: contextMenu.title,
        subtitle: contextMenu.subtitle,
        width: preferredWidth,
        height: preferredHeight,
        columns: columns,
        rows: rows
    )
}

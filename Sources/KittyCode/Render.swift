import KittyCodecs
import KittyRenderer
import KittyWidgets

@MainActor
func render(pipeline: RenderPipeline, state: EditorState) {
    let cols = pipeline.columns
    let rows = pipeline.rows
    state.lastRenderColumns = cols
    state.lastRenderRows = rows
    let colorScheme = state.colorScheme
    guard cols > 0 && rows > 1 else { return }

    // Layout calculations
    let layout = LayoutMetrics(state: state, columns: cols, rows: rows)
    let showTabRibbon = layout.showTabRibbon
    let contentStartRow = layout.contentStartRow
    let contentRows = layout.contentRows
    let activityBarWidth = layout.activityBarWidth
    let sidebarWidth = layout.sidebarWidth
    let editorStart = layout.editorStart
    let editorWidth = layout.editorWidth

    guard contentRows > 0 else { return }

    // Tab ribbon
    if showTabRibbon {
        let tabs = state.tabRibbonTabs()
        let theme = state.config.theme
        var tabStyle = TabRibbon.TabRibbonStyle()
        if let s = theme.resolvedStyle(theme.tabActiveForeground, bold: true) {
            tabStyle.activeStyle = s
        }
        if let s = theme.resolvedStyle(theme.tabInactiveForeground) {
            tabStyle.inactiveStyle = s
        }
        if let s = theme.resolvedStyle(theme.tabDirtyIndicator) {
            tabStyle.dirtyStyle = s
        }
        let ribbon = TabRibbon(
            tabs: tabs,
            activeIndex: state.bufferManager.activeIndex,
            scrollOffset: state.tabScrollOffset,
            style: tabStyle
        )
        let tabBg = Cell(character: " ", style: tabStyle.inactiveStyle)
        pipeline.buffer.fill(row: 0, col: 0, width: cols, height: 1, cell: tabBg)
        ribbon.render(
            to: &pipeline.buffer,
            in: Rect(x: editorStart, y: 0, width: editorWidth, height: 1)
        )
    }

    // Activity bar
    if activityBarWidth > 0 {
        renderActivityBar(
            pipeline: pipeline,
            state: state,
            rect: Rect(x: 0, y: contentStartRow, width: activityBarWidth, height: contentRows),
            colorScheme: colorScheme
        )
    }

    // Sidebar panel (tree or open files)
    if sidebarWidth > 0 {
        let sidebarRect = Rect(
            x: activityBarWidth, y: contentStartRow, width: sidebarWidth, height: contentRows)

        switch state.activeSidebarPanel {
        case .explorer:
            renderTreePanel(
                pipeline: pipeline,
                state: state,
                treeRect: sidebarRect,
                colorScheme: colorScheme
            )
        case .openDocuments:
            renderOpenFilesPanel(
                pipeline: pipeline,
                state: state,
                rect: sidebarRect,
                colorScheme: colorScheme
            )
        }

        // Separator
        let separatorCol = activityBarWidth + sidebarWidth
        for row in 0..<contentRows {
            pipeline.buffer.write(
                "\u{2502}", row: contentStartRow + row, col: separatorCol,
                style: colorScheme.separator)
        }
    }

    // Editor
    let terminalCursorPos = renderEditorPanel(
        pipeline: pipeline,
        state: state,
        editorStart: editorStart,
        editorWidth: editorWidth,
        contentStartRow: contentStartRow,
        contentRows: contentRows,
        colorScheme: colorScheme
    )

    // Status bar
    let statusSegments =
        state.config.statusBar.show
        ? state.statusBarSegments(columns: cols, rows: rows)
        : ("", state.contextHintText ?? "")
    StatusBar(
        left: statusSegments.0,
        right: statusSegments.1,
        style: colorScheme.statusBar
    ).render(to: &pipeline.buffer, in: Rect(x: 0, y: rows - 1, width: cols, height: 1))

    let overlayCursorPos = renderOverlay(
        pipeline: pipeline,
        state: state,
        columns: cols,
        rows: rows,
        colorScheme: colorScheme
    )

    if let pos = overlayCursorPos {
        pipeline.cursorRow = pos.row
        pipeline.cursorCol = pos.col
    } else if let pos = terminalCursorPos {
        pipeline.cursorRow = pos.row
        pipeline.cursorCol = pos.col
    } else {
        pipeline.cursorRow = nil
        pipeline.cursorCol = nil
    }
}

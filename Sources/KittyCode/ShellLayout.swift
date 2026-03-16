import KittyCodecs
import KittyRenderer
import KittyWidgets

struct ShellLayoutRects {
    var tabRibbon: Rect?
    var activityBar: Rect?
    var sidebar: Rect?
    var separator: Rect?
    var editor: Rect
    var statusBar: Rect
}

@MainActor
func computeShellLayout(state: EditorState, columns: Int, rows: Int) -> (rects: ShellLayoutRects, focusMap: FocusMap) {
    let layout = LayoutMetrics(state: state, columns: columns, rows: rows)
    let collector = FocusMapCollector()

    let tabRect: Rect? = layout.showTabRibbon
        ? Rect(x: 0, y: 0, width: columns, height: 1)
        : nil

    let activityBarRect: Rect? = layout.activityBarWidth > 0
        ? Rect(x: 0, y: layout.contentStartRow, width: layout.activityBarWidth, height: layout.contentRows)
        : nil

    let sidebarRect: Rect? = layout.sidebarWidth > 0
        ? Rect(x: layout.activityBarWidth, y: layout.contentStartRow, width: layout.sidebarWidth, height: layout.contentRows)
        : nil

    let separatorRect: Rect? = layout.sidebarWidth > 0
        ? Rect(x: layout.activityBarWidth + layout.sidebarWidth, y: layout.contentStartRow, width: 1, height: layout.contentRows)
        : nil

    let editorRect = Rect(
        x: layout.editorStart,
        y: layout.contentStartRow,
        width: layout.editorWidth,
        height: layout.contentRows
    )

    let statusBarRect = Rect(x: 0, y: rows - 1, width: columns, height: 1)

    // Build focus map
    if let r = tabRect { collector.register(.tabRibbon, rect: Rect(x: layout.editorStart, y: r.y, width: layout.editorWidth, height: 1)) }
    if let r = activityBarRect { collector.register(.activityBar, rect: r) }
    if let r = sidebarRect {
        if state.activeSidebarPanel == .search {
            collector.register(.searchPanel, rect: r)
        } else {
            collector.register(.sidebar, rect: r)
        }
    }
    collector.register(.editor, rect: editorRect)
    collector.register(.statusBar, rect: statusBarRect)

    let rects = ShellLayoutRects(
        tabRibbon: tabRect,
        activityBar: activityBarRect,
        sidebar: sidebarRect,
        separator: separatorRect,
        editor: editorRect,
        statusBar: statusBarRect
    )

    return (rects: rects, focusMap: collector.build())
}

@MainActor
func renderShellLayout(pipeline: RenderPipeline, state: EditorState) {
    let cols = pipeline.columns
    let rows = pipeline.rows
    state.lastRenderColumns = cols
    state.lastRenderRows = rows
    let colorScheme = state.colorScheme
    guard cols > 0 && rows > 1 else { return }

    let (shellRects, focusMap) = computeShellLayout(state: state, columns: cols, rows: rows)
    state.focusMap = focusMap

    let layout = LayoutMetrics(state: state, columns: cols, rows: rows)
    guard layout.contentRows > 0 else { return }

    // Tab ribbon
    if layout.showTabRibbon, let tabRect = shellRects.tabRibbon {
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
        pipeline.buffer.fill(row: tabRect.y, col: tabRect.x, width: cols, height: 1, cell: tabBg)
        ribbon.render(
            to: &pipeline.buffer,
            in: Rect(x: layout.editorStart, y: tabRect.y, width: layout.editorWidth, height: 1)
        )
    }

    // Activity bar
    if let abRect = shellRects.activityBar {
        renderActivityBar(
            pipeline: pipeline,
            state: state,
            rect: abRect,
            colorScheme: colorScheme
        )
    }

    // Sidebar panel
    var sidebarCursorPos: (row: Int, col: Int)?
    if let sidebarRect = shellRects.sidebar {
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
        case .search:
            sidebarCursorPos = renderSearchPanel(
                pipeline: pipeline,
                state: state,
                rect: sidebarRect,
                colorScheme: colorScheme
            )
        }
    }

    // Separator
    if let sepRect = shellRects.separator {
        for row in sepRect.y..<sepRect.maxY {
            pipeline.buffer.write(
                "\u{2502}", row: row, col: sepRect.x,
                style: colorScheme.separator)
        }
    }

    // Editor
    let terminalCursorPos = renderEditorPanel(
        pipeline: pipeline,
        state: state,
        editorStart: shellRects.editor.x,
        editorWidth: shellRects.editor.width,
        contentStartRow: shellRects.editor.y,
        contentRows: shellRects.editor.height,
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
    ).render(to: &pipeline.buffer, in: shellRects.statusBar)

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
    } else if state.mode == .searchPanel, let pos = sidebarCursorPos {
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

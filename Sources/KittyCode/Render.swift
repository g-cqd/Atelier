import KittyCodecs
import KittyRenderer
import KittySymbols
import KittyWidgets

@MainActor
func render(pipeline: RenderPipeline, state: EditorState) {
    let cols = pipeline.columns
    let rows = pipeline.rows
    let colorScheme = state.colorScheme
    guard cols > 0 && rows > 2 else { return }

    // Layout calculations
    let showActivityBar = state.config.activityBar.show && !state.sidebarCollapsed
    let activityBarWidth = showActivityBar ? ActivityBar.width : 0
    let showTabRibbon = state.config.tabRibbonPosition == .top && state.bufferManager.count > 0
    let tabRibbonRows = showTabRibbon ? 1 : 0
    let contentStartRow = 1 + tabRibbonRows
    let contentRows = rows - 2 - tabRibbonRows

    guard contentRows > 0 else { return }

    let sidebarWidth: Int
    if state.sidebarCollapsed {
        sidebarWidth = 0
    } else {
        sidebarWidth = min(state.treePanelWidth, cols / 2)
    }
    let totalSidebarWidth = activityBarWidth + sidebarWidth
    let separatorWidth = sidebarWidth > 0 ? 1 : 0
    let editorStart = totalSidebarWidth + separatorWidth
    let editorWidth = max(0, cols - editorStart)

    // Title bar
    StatusBar(
        left: " " + TerminalSymbolRenderer.label(state.symbolTheme[.project], "KittyCode") + " \(state.rootPath) ",
        style: colorScheme.titleBar
    ).render(to: &pipeline.buffer, in: Rect(x: 0, y: 0, width: cols, height: 1))

    // Tab ribbon
    if showTabRibbon {
        let tabs = state.bufferManager.buffers.map { buf in
            TabRibbon.Tab(name: buf.fileName, isDirty: buf.isDirty)
        }
        var tabStyle = TabRibbon.TabRibbonStyle()
        if let fg = state.config.theme.tabActiveForeground {
            tabStyle.activeStyle = Style(fg: fg.color, bold: true)
        }
        if let fg = state.config.theme.tabInactiveForeground {
            tabStyle.inactiveStyle = Style(fg: fg.color)
        }
        let ribbon = TabRibbon(
            tabs: tabs,
            activeIndex: state.bufferManager.activeIndex,
            scrollOffset: state.tabScrollOffset,
            style: tabStyle
        )
        // Fill row 1 background across full width, then render tabs over editor area
        let tabBg = Cell(character: " ", style: tabStyle.inactiveStyle)
        pipeline.buffer.fill(row: 1, col: 0, width: cols, height: 1, cell: tabBg)
        ribbon.render(
            to: &pipeline.buffer,
            in: Rect(x: editorStart, y: 1, width: editorWidth, height: 1)
        )
    }

    // Activity bar
    if showActivityBar {
        renderActivityBar(
            pipeline: pipeline,
            state: state,
            rect: Rect(x: 0, y: contentStartRow, width: activityBarWidth, height: contentRows),
            colorScheme: colorScheme
        )
    }

    // Sidebar panel (tree or open files)
    if sidebarWidth > 0 {
        let sidebarRect = Rect(x: activityBarWidth, y: contentStartRow, width: sidebarWidth, height: contentRows)

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
            pipeline.buffer.write("\u{2502}", row: contentStartRow + row, col: separatorCol, style: colorScheme.separator)
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
    let modeGlyph = state.mode == .tree ? state.symbolTheme[.modeTree] : state.symbolTheme[.modeEdit]
    let mode = state.mode == .tree ? "Tree" : "Edit"
    let position = state.isFileEmpty ? "" : "Ln \(state.cursorRow + 1)/\(state.fileLineCount)"
    let statusLeft = " " + TerminalSymbolRenderer.label(modeGlyph, mode) + "  \(state.statusMessage)"
    let branchSegment: String? = state.fileStatusProvider?.branchName.map { name in
        TerminalSymbolRenderer.label(state.symbolTheme[.gitBranch], name)
    }
    let tabInfo = state.bufferManager.count > 1 ? "[\(state.bufferManager.activeIndex + 1)/\(state.bufferManager.count)]" : nil
    let statusRightCore = [
        tabInfo,
        branchSegment,
        position.isEmpty ? nil : TerminalSymbolRenderer.label(state.symbolTheme[.position], position),
        TerminalSymbolRenderer.label(state.symbolTheme[.dimensions], "\(cols)x\(rows)")
    ].compactMap { $0 }.joined(separator: "  ")
    let statusRight = statusRightCore + " "
    StatusBar(
        left: statusLeft,
        right: statusRight,
        style: colorScheme.statusBar
    ).render(to: &pipeline.buffer, in: Rect(x: 0, y: rows - 1, width: cols, height: 1))

    if let pos = terminalCursorPos {
        pipeline.cursorRow = pos.row
        pipeline.cursorCol = pos.col
    } else {
        pipeline.cursorRow = nil
        pipeline.cursorCol = nil
    }
}

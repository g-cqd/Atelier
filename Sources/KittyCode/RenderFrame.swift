import KittyRenderer
import KittyWidgets

/// Tracks the previous frame's visual scroll offset for terminal scroll optimization.
@MainActor private var lastVisualScrollOffset = 0

@MainActor
func renderFrame(pipeline: RenderPipeline, state: EditorState) {
    pipeline.beginFrame()
    state.lastRenderColumns = pipeline.columns
    state.lastRenderRows = pipeline.rows

    let layout = LayoutMetrics(state: state, columns: pipeline.columns, rows: pipeline.rows)

    // Compute the current visual scroll offset (accounts for wrap mode).
    let currentVisualOffset: Int
    if state.config.editor.wrapLines {
        let contentWidth = max(
            1, layout.editorWidth - TextEditorLayout.gutterWidth(for: makeEditorView(state: state)))
        state.buildWrapCache(contentWidth: contentWidth)
        currentVisualOffset =
            state.visualRowOffset(forLine: state.scrollOffset) + state.wrapRowOffset
    } else {
        currentVisualOffset = state.scrollOffset
    }

    let delta = currentVisualOffset - lastVisualScrollOffset
    if delta != 0, abs(delta) < layout.contentRows {
        pipeline.scrollHint = ScrollHint(
            regionTop: layout.contentStartRow,
            regionHeight: layout.contentRows,
            delta: delta
        )
    }
    lastVisualScrollOffset = currentVisualOffset

    render(pipeline: pipeline, state: state)
}

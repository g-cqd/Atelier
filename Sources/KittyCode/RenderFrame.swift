import KittyRenderer
import KittyWidgets

/// Tracks scroll offsets from the previous frame for pre-shift optimisation.
@MainActor private var lastEditorScrollOffset = 0
@MainActor private var lastEditorWrapRowOffset = 0
@MainActor private var lastEditorVisualRowOffset = 0

@MainActor
func renderFrame(pipeline: RenderPipeline, state: EditorState) {
    pipeline.beginFrame()
    state.lastRenderColumns = pipeline.columns
    state.lastRenderRows = pipeline.rows

    let layout = LayoutMetrics(state: state, columns: pipeline.columns, rows: pipeline.rows)

    // Pre-shift editor rows so the diff only covers newly exposed lines.
    if state.config.editor.wrapLines {
        state.buildWrapCache(contentWidth: layout.editorWidth - TextEditorLayout.gutterWidth(for: makeEditorView(state: state)))
        let currentVisualOffset = state.visualRowOffset(forLine: state.scrollOffset) + state.wrapRowOffset
        let delta = currentVisualOffset - lastEditorVisualRowOffset
        if delta != 0, abs(delta) < layout.contentRows {
            pipeline.buffer.shiftRows(
                regionY: layout.contentStartRow,
                regionHeight: layout.contentRows,
                regionX: layout.editorStart,
                regionWidth: layout.editorWidth,
                delta: delta
            )
        }
        lastEditorVisualRowOffset = currentVisualOffset
    } else {
        let delta = state.scrollOffset - lastEditorScrollOffset
        if delta != 0, abs(delta) < layout.contentRows {
            pipeline.buffer.shiftRows(
                regionY: layout.contentStartRow,
                regionHeight: layout.contentRows,
                regionX: layout.editorStart,
                regionWidth: layout.editorWidth,
                delta: delta
            )
        }
        lastEditorScrollOffset = state.scrollOffset
    }

    render(pipeline: pipeline, state: state)
}

import Foundation
import KittyRenderer
import KittyWidgets

/// Tracks the previous frame's visual scroll offset for terminal scroll optimization.
@MainActor private var lastVisualScrollOffset = 0

@MainActor
func renderFrame(pipeline: RenderPipeline, state: EditorState) {
    // Clear expired command feedback (mark chrome dirty if we actually changed
    // anything — otherwise an idle frame stays idle).
    if let expiry = state.commandFeedbackExpiry, ContinuousClock.now >= expiry {
        state.commandFeedback = nil
        state.commandFeedbackExpiry = nil
        state.markChromeDirty()
    }

    // Snapshot what state explicitly marked as changed since the last frame.
    // Phase 3 wires the drain through to the pipeline; Phase 4+ will use the
    // regions to skip per-cell work. For now we keep the full repaint so any
    // state mutation that has not yet been hooked into the dirty tracker
    // continues to render correctly.
    let dirty = state.drainDirtyState()

    pipeline.beginFrame()
    state.lastRenderColumns = pipeline.columns
    state.lastRenderRows = pipeline.rows

    let layout = LayoutMetrics(state: state, columns: pipeline.columns, rows: pipeline.rows)

    // Translate logical dirty info into pipeline-level rects. Phase 3 only
    // marks them; later phases use the data to bypass per-cell work.
    pipeline.clearDirtyRegions()
    if dirty.contentAll || dirty.chrome {
        pipeline.markAllDirty()
    } else {
        for line in dirty.contentLines {
            let screenRow = line - state.scrollOffset + layout.contentStartRow
            if screenRow >= layout.contentStartRow && screenRow < pipeline.rows - 1 {
                pipeline.markDirty(
                    DirtyRect(
                        row: screenRow, col: layout.editorStart,
                        height: 1, width: layout.editorWidth))
            }
        }
    }

    // Compute the current visual scroll offset (accounts for wrap mode).
    let currentVisualOffset: Int
    if state.config.editor.wrapLines {
        _ = state.resolvedWrapContentWidth(columns: pipeline.columns, rows: pipeline.rows)
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

    renderShellLayout(pipeline: pipeline, state: state)
}

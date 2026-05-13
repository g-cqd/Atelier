import Foundation
import KittyRenderer
import KittyWidgets

/// Tracks the previous frame's visual scroll offset for terminal scroll optimization.
@MainActor private var lastVisualScrollOffset = 0

/// State captured from the last successful `renderFrame` so the next call can
/// skip when nothing visibly changed. `nil` until the first render so we
/// always paint at least once.
@MainActor private var lastRenderedSignature: RenderSignature?

/// Lightweight view of state values that, when unchanged between frames AND
/// with empty dirty markers, indicate the screen would be byte-identical.
private struct RenderSignature: Equatable {
    var cursorRow: Int
    var cursorCol: Int
    var scrollOffset: Int
    var hScrollOffset: Int
    var wrapRowOffset: Int
    var columns: Int
    var rows: Int

    @MainActor
    init(state: EditorState, pipeline: RenderPipeline) {
        self.cursorRow = state.cursorRow
        self.cursorCol = state.cursorCol
        self.scrollOffset = state.scrollOffset
        self.hScrollOffset = state.hScrollOffset
        self.wrapRowOffset = state.wrapRowOffset
        self.columns = pipeline.columns
        self.rows = pipeline.rows
    }
}

@MainActor
func renderFrame(pipeline: RenderPipeline, state: EditorState) {
    // Detect viewport resize. SIGWINCH delivers `.resize(...)` which
    // ApplicationRuntime applies via `pipeline.resize(...)` before invoking
    // the render callback — but the editor's logical dirty markers don't
    // know about the new dimensions, so Phase 6b's `skipChromeSections` gate
    // would otherwise leave chrome stale on the resized buffer. Compare
    // against the last render's dims and escalate to a full repaint.
    if state.lastRenderColumns != pipeline.columns || state.lastRenderRows != pipeline.rows {
        state.markEverythingDirty()
    }

    // Clear expired command feedback (mark chrome dirty if we actually changed
    // anything — otherwise an idle frame stays idle).
    if let expiry = state.commandFeedbackExpiry, ContinuousClock.now >= expiry {
        state.commandFeedback = nil
        state.commandFeedbackExpiry = nil
        state.markChromeDirty()
    }

    let dirty = state.drainDirtyState()
    let signature = RenderSignature(state: state, pipeline: pipeline)
    let nothingDirty =
        !dirty.contentAll && !dirty.chrome && dirty.contentLines.isEmpty
            && pipeline.scrollHint == nil
    if nothingDirty, let last = lastRenderedSignature, last == signature {
        // No state mutation marked dirty and the inter-frame signature has not
        // drifted (cursor / scroll / viewport unchanged). The previous frame is
        // still the correct frame; skip the entire paint.
        return
    }
    lastRenderedSignature = signature

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

    renderShellLayout(
        pipeline: pipeline, state: state,
        skipChromeSections: !dirty.contentAll && !dirty.chrome
    )
}

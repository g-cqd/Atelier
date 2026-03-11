import KittyRenderer
import KittyWidgets

@MainActor
func renderFrame(pipeline: RenderPipeline, state: EditorState) {
    pipeline.beginFrame()
    state.lastRenderColumns = pipeline.columns
    state.lastRenderRows = pipeline.rows
    render(pipeline: pipeline, state: state)
}

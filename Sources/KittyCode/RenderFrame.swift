import KittyRenderer

@MainActor
func renderFrame(pipeline: RenderPipeline, state: EditorState) {
    pipeline.beginFrame()
    render(pipeline: pipeline, state: state)
}

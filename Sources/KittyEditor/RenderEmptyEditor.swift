import KittyCodecs
import KittyRenderer
import KittyWidgets

@MainActor
public func renderEmptyEditor(
    pipeline: RenderPipeline,
    editorStart: Int,
    editorWidth: Int,
    contentStartRow: Int,
    contentRows: Int,
    colorScheme: EditorState.ColorScheme
) {
    CenteredText(
        text: "Open a file from the tree (Enter) or create one (^N)",
        style: colorScheme.emptyEditorMessage,
        backgroundStyle: colorScheme.editorText
    ).render(
        to: &pipeline.buffer,
        in: Rect(x: editorStart, y: contentStartRow, width: editorWidth, height: contentRows)
    )
}

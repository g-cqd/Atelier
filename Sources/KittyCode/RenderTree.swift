import KittyCodecs
import KittyFileTree
import KittyRenderer

@MainActor
func renderTreePanel(
    pipeline: RenderPipeline,
    state: EditorState,
    treeWidth: Int,
    contentRows: Int,
    colorScheme: EditorState.ColorScheme
) {
    for row in 0..<contentRows {
        let treeIndex = state.treeScrollOffset + row
        if treeIndex >= 0 && treeIndex < state.cachedFlatTree.count {
            let (depth, node) = state.cachedFlatTree[treeIndex]
            let indent = String(repeating: " ", count: depth * 2)
            let label = indent + node.icon + " " + node.name
            let padded = label + String(repeating: " ", count: max(0, treeWidth - label.count))
            let style: Style
            if treeIndex == state.selectedTreeIndex {
                style = colorScheme.treeSelected
            } else if node.isDirectory {
                style = colorScheme.treeDir
            } else {
                style = colorScheme.treeBg
            }
            pipeline.buffer.write(String(padded.prefix(treeWidth)), row: row + 1, col: 0, style: style)
        } else {
            pipeline.buffer.fill(row: row + 1, col: 0, width: treeWidth, height: 1, cell: Cell(character: " ", style: colorScheme.treeBg))
        }

        pipeline.buffer.write("│", row: row + 1, col: treeWidth, style: colorScheme.separator)
    }
}
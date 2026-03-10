import KittyCodecs
import KittyFileTree
import KittyRenderer
import KittyWidgets

@MainActor
func renderTreePanel(
    pipeline: RenderPipeline,
    state: EditorState,
    treeWidth: Int,
    contentRows: Int,
    colorScheme: EditorState.ColorScheme
) {
    let root = state.treeNodes.map(makeTreeNode)
    let view = TreeView(
        root: root,
        selectedIndex: state.selectedTreeIndex,
        scrollOffset: state.treeScrollOffset,
        style: TreeView<FileNode>.TreeViewStyle(
            normalStyle: colorScheme.treeBg,
            selectedStyle: colorScheme.treeSelected,
            expandedIcon: "[-]",
            collapsedIcon: "[+]",
            leafIcon: "   ",
            indent: 2
        ),
        label: { $0.name },
        rowStyle: { $0.isDirectory ? colorScheme.treeDir : colorScheme.treeBg }
    )
    view.render(to: &pipeline.buffer, in: Rect(x: 0, y: 1, width: treeWidth, height: contentRows))

    for row in 0..<contentRows {
        pipeline.buffer.write("│", row: row + 1, col: treeWidth, style: colorScheme.separator)
    }
}

private func makeTreeNode(_ node: FileNode) -> TreeNode<FileNode> {
    TreeNode(value: node, children: node.children.map(makeTreeNode), isExpanded: node.isExpanded)
}

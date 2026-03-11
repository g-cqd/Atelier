import KittyCodecs
import KittyFileTree
import KittyRenderer
import KittySymbols
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
    let provider = state.fileStatusProvider
    let view = TreeView(
        root: root,
        selectedIndex: state.selectedTreeIndex,
        scrollOffset: state.treeScrollOffset,
        showsVerticalScrollIndicator: true,
        style: TreeView<FileNode>.TreeViewStyle(
            normalStyle: colorScheme.treeBg,
            selectedStyle: colorScheme.treeSelected,
            expandedIcon: state.symbolTheme[.folderOpen].text + " ",
            collapsedIcon: state.symbolTheme[.folderClosed].text + " ",
            leafIcon: state.symbolTheme[.file].text + " ",
            indent: 2,
            scrollIndicatorStyle: VerticalScrollIndicatorStyle(
                trackStyle: Style(fg: .rgb(r: 60, g: 60, b: 60), dim: true),
                thumbStyle: Style(fg: .rgb(r: 140, g: 140, b: 140), dim: true),
                trackCharacter: " ",
                thumbCharacter: "▓"
            )
        ),
        label: { $0.name },
        rowStyle: { $0.isDirectory ? colorScheme.treeDir : colorScheme.treeBg },
        rowSuffix: { node in
            provider?.status(for: node.path)?.indicator ?? ""
        },
        rowSuffixStyle: { node in
            guard let status = provider?.status(for: node.path) else {
                return colorScheme.treeBg
            }
            return colorScheme.gitStatusStyle(for: status.statusColor)
        }
    )
    view.render(to: &pipeline.buffer, in: Rect(x: 0, y: 1, width: treeWidth, height: contentRows))

    for row in 0..<contentRows {
        pipeline.buffer.write("│", row: row + 1, col: treeWidth, style: colorScheme.separator)
    }
}

private func makeTreeNode(_ node: FileNode) -> TreeNode<FileNode> {
    TreeNode(value: node, children: node.children.map(makeTreeNode), isExpanded: node.isExpanded)
}

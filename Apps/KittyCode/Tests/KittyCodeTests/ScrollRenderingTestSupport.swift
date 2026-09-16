import Foundation
import KittyCodecs
import KittyFileTree
import KittyGit
import KittyRenderer
import KittySyntax
import KittyTerminal
import KittyText
import KittyWidgets
import KittyWorkspace
import Testing

@testable import KittyEditor

@MainActor
func makeScrollRenderingContext(
    lineCount: Int = 100,
    columns: Int = 40,
    rows: Int = 12
) -> (state: EditorState, pipeline: RenderPipeline) {
    var config = KittyConfig()
    config.activityBar.show = false
    config.tabRibbon.position = .hidden
    config.statusBar.show = false
    let state = EditorState(rootPath: ".", config: config)
    state.sidebarCollapsed = true
    state.mode = .editor
    state.fileContent = (0..<lineCount).map { "line \($0) content here" }
    state.refreshHighlights()
    let pipeline = RenderPipeline(
        connection: MockTerminalConnection(size: TerminalSize(columns: columns, rows: rows)),
        columns: columns,
        rows: rows
    )
    return (state, pipeline)
}

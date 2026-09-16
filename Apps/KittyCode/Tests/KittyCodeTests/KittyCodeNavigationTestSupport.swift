import AtelierText
import Foundation
import KittyCodecs
import KittyFileTree
import KittyGit
import KittyRenderer
import KittySyntax
import KittyTerminal
import KittyWidgets
import KittyWorkspace
import Testing

@testable import KittyEditor

@MainActor
func makeKittyCodeNavigationContext(
    fileContent: [String],
    columns: Int = 80,
    rows: Int = 24
) -> (state: EditorState, pipeline: RenderPipeline) {
    var config = KittyConfig()
    config.activityBar.show = false
    config.tabRibbon.position = .hidden
    let state = EditorState(rootPath: ".", config: config)
    state.mode = .editor
    state.fileContent = fileContent

    let pipeline = RenderPipeline(
        connection: MockTerminalConnection(size: TerminalSize(columns: columns, rows: rows)),
        columns: columns,
        rows: rows
    )

    return (state, pipeline)
}

@MainActor
func settlePendingAcceleratedScroll(_ state: EditorState) {
    drainPendingAcceleratedScroll(state: state)
}

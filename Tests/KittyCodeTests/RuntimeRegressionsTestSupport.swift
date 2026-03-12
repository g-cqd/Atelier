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

@testable import KittyCode

@MainActor
func makeRuntimeRegressionContext(
    fileContent: [String] = [""],
    columns: Int = 80,
    rows: Int = 24,
    activityBar: Bool = false,
    tabRibbon: KittyConfig.TabRibbonPosition = .hidden
) -> (state: EditorState, pipeline: RenderPipeline) {
    var config = KittyConfig()
    config.activityBar.show = activityBar
    config.tabRibbon.position = tabRibbon
    let state = EditorState(rootPath: ".", config: config)
    state.fileContent = fileContent
    let pipeline = RenderPipeline(
        connection: MockTerminalConnection(size: TerminalSize(columns: columns, rows: rows)),
        columns: columns,
        rows: rows
    )
    return (state, pipeline)
}

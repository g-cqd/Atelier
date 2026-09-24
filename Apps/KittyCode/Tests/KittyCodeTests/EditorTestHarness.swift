import AemiCore
import AemiTesting
import AtelierGit
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

/// The factory for the `EditorState` and `RenderPipeline` pairs the suites test. `taskProvider` and `clock` default
/// to the real runtime; pass `TaskProviderSpy()` and `TestClock()` to control background work deterministically.
@MainActor
enum EditorTestHarness {
    /// The general builder; by default the activity bar and tab ribbon are hidden and the status bar is shown, in
    /// `.editor` mode.
    static func make(
        rootPath: String = ".",
        fileContent: [String]? = nil,
        columns: Int = 80,
        rows: Int = 24,
        activityBar: Bool = false,
        tabRibbon: KittyConfig.TabRibbonPosition = .hidden,
        statusBar: Bool = true,
        mode: EditorState.Mode = .editor,
        sidebarCollapsed: Bool = false,
        refreshHighlightsAfterContent: Bool = false,
        taskProvider: any TaskProvider = .default,
        clock: any Clock<Duration> = ContinuousClock()
    ) -> (state: EditorState, pipeline: RenderPipeline) {
        var config = KittyConfig()
        config.activityBar.show = activityBar
        config.tabRibbon.position = tabRibbon
        config.statusBar.show = statusBar
        let state = EditorState(
            rootPath: rootPath, config: config, taskProvider: taskProvider, clock: clock,
            searchPool: EditorTestPool.shared)
        state.mode = mode
        state.sidebarCollapsed = sidebarCollapsed
        if let fileContent {
            state.fileContent = fileContent
        }
        if refreshHighlightsAfterContent {
            state.refreshHighlights()
        }

        let pipeline = RenderPipeline(
            connection: MockTerminalConnection(size: TerminalSize(columns: columns, rows: rows)),
            columns: columns,
            rows: rows
        )
        return (state, pipeline)
    }

    /// A synthetic `lineCount`-line file with the sidebar collapsed, the status bar hidden and highlights refreshed
    /// up front, since the scroll-diff tests read `highlightedLines` before any render.
    static func makeScrollRendering(
        lineCount: Int = 100,
        columns: Int = 40,
        rows: Int = 12
    ) -> (state: EditorState, pipeline: RenderPipeline) {
        make(
            fileContent: (0 ..< lineCount).map { "line \($0) content here" },
            columns: columns,
            rows: rows,
            statusBar: false,
            sidebarCollapsed: true,
            refreshHighlightsAfterContent: true
        )
    }

    @MainActor
    static func settlePendingAcceleratedScroll(_ state: EditorState) {
        drainPendingAcceleratedScroll(state: state)
    }
}

/// Fake `FileStatusProvider`/`GitLineDecorationProvider` the git-decoration and status-bar suites wire
/// onto a harness-built `EditorState` in place of a real `GitStatusProvider`.
struct TestGitProvider: FileStatusProvider, GitLineDecorationProvider {
    var statuses: [String: FileStatus] = [:]
    var decorations: [String: GitLineDecorations] = [:]
    var branchName: String? = nil
    var summary: FileStatusSummary = .init()

    func status(for path: String) -> FileStatus? {
        statuses[path]
    }

    func refresh() async {}

    func lineDecorations(for path: String, lines _: [String]) async -> GitLineDecorations {
        decorations[path] ?? .empty
    }
}

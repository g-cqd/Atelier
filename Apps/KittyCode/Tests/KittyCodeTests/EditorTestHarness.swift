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

/// Single factory for the `EditorState` + `RenderPipeline` pairs `KittyCodeTests` suites build as
/// their system under test. Replaces four near-duplicate `make*Context` factories (Audit test-support
/// consolidation) that differed only in which `KittyConfig` knobs they toggled and whether they set an
/// initial mode / collapsed the sidebar / eagerly refreshed highlights — every one of those knobs is a
/// parameter here instead. `taskProvider`/`clock` default to the real runtime (`.default` /
/// `ContinuousClock()`, unchanged from every prior factory); pass `TaskProviderSpy()` / `TestClock()`
/// (`AemiTesting`) when a test needs deterministic control over background work instead of letting it
/// run free, matching the app-tier testing convention in `AGENTS.md`.
@MainActor
enum EditorTestHarness {
    /// General-purpose builder. Defaults reproduce the old `makeKittyCodeNavigationContext` shape (the
    /// most common one): activity bar and tab ribbon hidden, `.editor` mode, status bar shown.
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
            rootPath: rootPath, config: config, taskProvider: taskProvider, clock: clock)
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

    /// The old `makeScrollRenderingContext` shape: a synthetic `lineCount`-line file, sidebar
    /// collapsed, status bar hidden, highlights refreshed eagerly (the scroll-diff tests assert
    /// against `highlightedLines` immediately, before any render pass would otherwise populate it).
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

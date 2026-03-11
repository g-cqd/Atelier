import Foundation
import KittyApp
import KittyGit
import KittyRenderer
import KittyTerminal

@main
struct KittyCodeEntry {
    static func main() async {
        do {
            try await runEditor()
        } catch {
            let msg = "CRASH: \(error)\n"
            let crashPath = FileManager.default.temporaryDirectory
                .appendingPathComponent("kittycode-crash-\(ProcessInfo.processInfo.processIdentifier).log")
            try? msg.write(to: crashPath, atomically: true, encoding: .utf8)
            FileHandle.standardError.write(Data(msg.utf8))
        }
    }

    @MainActor static func runEditor() async throws {
        let args = CommandLine.arguments
        let rootPath: String
        if args.count > 1 {
            rootPath = args[1]
        } else {
            rootPath = FileManager.default.currentDirectoryPath
        }

        let config = KittyConfig.load()
        let state = EditorState(rootPath: rootPath, config: config)
        await state.loadInitialTree()
        let refreshSource = RenderRefreshSource()
        state.renderRefreshSource = refreshSource

        if config.showGitStatus, let repositoryRoot = GitStatusProvider.repositoryRoot(for: rootPath) {
            let gitProvider = GitStatusProvider(rootPath: repositoryRoot)
            state.fileStatusProvider = gitProvider
            state.gitLineDecorationProvider = gitProvider
            state.gitDecorationManager = GitDecorationManager(state: state, refreshSource: refreshSource)
        }

        // File watcher (Phase 3)
        var fileWatcherIntegration: FileWatcherIntegration?
        if config.fileWatcherEnabled {
            let watcher = FileWatcher()
            let integration = FileWatcherIntegration(watcher: watcher, state: state)
            integration.start()
            fileWatcherIntegration = integration
        }

        // Auto-save (Phase 5)
        var autoSaveManager: AutoSaveManager?
        if config.autoSave {
            let manager = AutoSaveManager(state: state, fileWatcherIntegration: fileWatcherIntegration)
            manager.start()
            autoSaveManager = manager
        }

        // Git refresh (Phase 6)
        var gitRefreshManager: GitRefreshManager?
        if config.showGitStatus, state.fileStatusProvider != nil {
            let manager = GitRefreshManager(state: state, refreshSource: refreshSource)
            manager.refreshNow()
            manager.start()
            gitRefreshManager = manager
        }

        let connection = POSIXTerminalConnection()
        let runtime = ApplicationRuntime(connection: connection)

        try await runtime.run(
            render: { pipeline in
                pipeline.buffer.clear()
                render(pipeline: pipeline, state: state)
            },
            onEvent: { event, pipeline in
                let shouldContinue = handleEvent(event: event, state: state, pipeline: pipeline)
                if shouldContinue {
                    render(pipeline: pipeline, state: state)
                }
                return shouldContinue
            },
            configureInputSource: { inputSource in
                refreshSource.bind(inputSource: inputSource)
            }
        )

        // Cleanup
        autoSaveManager?.stop()
        gitRefreshManager?.stop()
        state.gitDecorationManager?.stop()
        fileWatcherIntegration?.stop()

        // Suppress unused variable warnings
        _ = autoSaveManager
        _ = gitRefreshManager
        _ = fileWatcherIntegration
    }
}

import Foundation
import KittyApp
import KittyFileTree
import KittyGit
import KittyRenderer
import KittyTerminal
import KittyWorkspace

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

        if config.git.enabled, let repositoryRoot = GitStatusProvider.repositoryRoot(for: rootPath) {
            let gitProvider = GitStatusProvider(rootPath: repositoryRoot)
            state.fileStatusProvider = gitProvider
            state.gitLineDecorationProvider = gitProvider
            state.gitDecorationManager = GitDecorationManager(
                workspace: state.workspace,
                gitConfig: GitDecorationConfig(
                    showGitStatus: config.git.enabled,
                    showLineChanges: config.git.decorations.showLineChanges,
                    lineChangeDebounceMilliseconds: config.git.decorations.lineChangeDebounceMilliseconds,
                    maxLineDiffBytes: config.git.decorations.maxLineDiffBytes
                ),
                gitLineDecorationProvider: gitProvider,
                invalidateRender: { [refreshSource] in refreshSource.invalidate() }
            )
        }

        // Config file watcher
        let configWatcher = FileWatcher()
        let configPath = KittyConfig.configURL.path
        let configWatchTask: Task<Void, Never>?
        if FileManager.default.fileExists(atPath: configPath) {
            await configWatcher.watchFile(configPath)
            configWatchTask = Task { @MainActor in
                for await event in configWatcher.events {
                    guard case .fileChanged = event else { continue }
                    let newConfig = KittyConfig.load()
                    state.applyConfig(newConfig)
                    refreshSource.invalidate()
                }
            }
        } else {
            configWatchTask = nil
        }

        // File watcher (Phase 3)
        var fileWatcherIntegration: FileWatcherIntegration?
        if config.fileWatcherEnabled {
            let watcher = FileWatcher()
            let integration = FileWatcherIntegration(watcher: watcher, workspace: state.workspace, delegate: state)
            integration.start()
            state.fileWatcherIntegration = integration
            fileWatcherIntegration = integration
        }

        // Auto-save (Phase 5)
        var autoSaveManager: AutoSaveManager?
        if config.autoSave.enabled {
            let manager = AutoSaveManager(
                workspace: state.workspace,
                fileWatcherIntegration: fileWatcherIntegration,
                autoSaveInterval: config.autoSave.interval,
                saveActiveBuffer: { [weak state] in state?.writeBufferToDisk() }
            )
            manager.start()
            autoSaveManager = manager
        }

        // Git refresh (Phase 6)
        var gitRefreshManager: GitRefreshManager?
        if config.git.enabled, state.fileStatusProvider != nil {
            let manager = GitRefreshManager(
                fileStatusProvider: state.fileStatusProvider,
                gitDecorationManager: state.gitDecorationManager,
                refreshInterval: config.git.refreshInterval,
                invalidateRender: { [refreshSource] in refreshSource.invalidate() }
            )
            manager.refreshNow()
            manager.start()
            gitRefreshManager = manager
        }

        let connection = POSIXTerminalConnection()
        let runtime = ApplicationRuntime(connection: connection)
        state.terminalWriter = { bytes in
            try? connection.write(Array(Data(bytes)))
        }

        try await runtime.run(
            render: { pipeline in
                renderFrame(pipeline: pipeline, state: state)
            },
            onEvent: { event, pipeline in
                let shouldContinue = handleEvent(event: event, state: state, pipeline: pipeline)
                if shouldContinue {
                    renderFrame(pipeline: pipeline, state: state)
                }
                return shouldContinue
            },
            configureInputSource: { inputSource in
                refreshSource.bind(inputSource: inputSource)
            }
        )

        // Cleanup
        configWatchTask?.cancel()
        await configWatcher.stop()
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

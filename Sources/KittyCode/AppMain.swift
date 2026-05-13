import Foundation
import KittyApp
import KittyCodecs
import KittyFileTree
import KittyGit
import KittyRenderer
import KittyTerminal
import KittyWorkspace

@main
struct KittyCodeEntry {
    static func main() async {
        let action = CLIArguments.parse()

        switch action {
        case .printVersion:
            print(CLIArguments.versionString)
            return
        case .printHelp:
            print(CLIArguments.helpText)
            return
        case .run(let launchConfig):
            do {
                try await runEditor(launchConfig: launchConfig)
            } catch {
                let msg = "CRASH: \(error)"
                let crashPath = FileManager.default.temporaryDirectory
                    .appendingPathComponent(
                        "kittycode-crash-\(ProcessInfo.processInfo.processIdentifier).log")
                try? (msg + "\n").write(to: crashPath, atomically: true, encoding: .utf8)
                KittyLogger.stderr(msg)
            }
        }
    }

    @MainActor static func runEditor(launchConfig: CLIArguments.LaunchConfig) async throws {
        var config = loadConfig(launchConfig: launchConfig)
        applyOverrides(from: launchConfig, to: &config)

        let state = EditorState(rootPath: launchConfig.rootPath, config: config)
        state.readOnly = launchConfig.readOnly

        await state.loadInitialTree()
        let refreshSource = RenderRefreshSource()
        state.renderRefreshSource = refreshSource
        let renderClock = RenderClock()
        state.renderClock = renderClock

        if config.git.enabled,
            let repositoryRoot = await GitStatusProvider.repositoryRoot(for: launchConfig.rootPath)
        {
            let gitProvider = GitStatusProvider(rootPath: repositoryRoot)
            state.fileStatusProvider = gitProvider
            state.gitLineDecorationProvider = gitProvider
            state.gitDecorationManager = GitDecorationManager(
                workspace: state.workspace,
                gitConfig: GitDecorationConfig(
                    showGitStatus: config.git.enabled,
                    showLineChanges: config.git.decorations.showLineChanges,
                    lineChangeDebounceMilliseconds: config.git.decorations
                        .lineChangeDebounceMilliseconds,
                    maxLineDiffBytes: config.git.decorations.maxLineDiffBytes
                ),
                gitLineDecorationProvider: gitProvider,
                invalidateRender: { [refreshSource] in refreshSource.invalidate() }
            )
        }

        // Config file watcher
        let configWatcher = FileWatcher()
        let configURL =
            launchConfig.configPath.map { URL(fileURLWithPath: $0) } ?? KittyConfig.configURL
        let configPath = configURL.path
        let configWatchTask: Task<Void, Never>?
        if FileManager.default.fileExists(atPath: configPath) {
            await configWatcher.watchFile(configPath)
            configWatchTask = Task { @MainActor in
                for await event in configWatcher.events {
                    guard case .fileChanged = event else { continue }
                    var newConfig = KittyConfig.load(from: configURL)
                    applyOverrides(from: launchConfig, to: &newConfig)
                    state.applyConfig(newConfig)
                    refreshSource.invalidate()
                }
            }
        } else {
            configWatchTask = nil
        }

        // File watcher
        var fileWatcherIntegration: FileWatcherIntegration?
        if config.fileWatcherEnabled {
            let watcher = FileWatcher()
            let integration = FileWatcherIntegration(
                watcher: watcher, workspace: state.workspace, delegate: state)
            integration.start()
            state.fileWatcherIntegration = integration
            fileWatcherIntegration = integration
        }

        // Auto-save (disabled in read-only mode)
        var autoSaveManager: AutoSaveManager?
        if config.autoSave.enabled && !launchConfig.readOnly {
            let manager = AutoSaveManager(
                workspace: state.workspace,
                fileWatcherIntegration: fileWatcherIntegration,
                autoSaveInterval: config.autoSave.interval,
                saveActiveBuffer: { [weak state] in state?.writeBufferToDisk() }
            )
            manager.start()
            autoSaveManager = manager
        }

        // Git refresh
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

        // Open initial file if specified
        if let filePath = launchConfig.initialFile {
            let fileName = URL(fileURLWithPath: filePath).lastPathComponent
            state.openFilePath(filePath, name: fileName)
        }

        let connection = POSIXTerminalConnection()
        let runtime = ApplicationRuntime(connection: connection)
        state.terminalWriter = { bytes in
            try? connection.write(Array(Data(bytes)))
        }

        // Position cursor after initial file opens (handled in event loop via render)
        if let line = launchConfig.initialLine {
            let targetRow = max(0, line - 1)
            let targetCol = max(0, (launchConfig.initialColumn ?? 1) - 1)
            state.cursorRow = min(targetRow, max(0, state.fileLineCount - 1))
            state.cursorCol = targetCol
            state.scrollOffset = max(0, state.cursorRow - 10)
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
            },
            renderClock: renderClock
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

    // MARK: - Private helpers

    private static func loadConfig(launchConfig: CLIArguments.LaunchConfig) -> KittyConfig {
        if let customPath = launchConfig.configPath {
            return KittyConfig.load(from: URL(fileURLWithPath: customPath))
        }
        return KittyConfig.load()
    }

    private static func applyOverrides(
        from launchConfig: CLIArguments.LaunchConfig, to config: inout KittyConfig
    ) {
        if let gitEnabled = launchConfig.gitEnabled {
            config.git.enabled = gitEnabled
        }
        if let syntaxEnabled = launchConfig.syntaxEnabled {
            config.syntax.enabled = syntaxEnabled
        }
        if let fileWatcherEnabled = launchConfig.fileWatcherEnabled {
            config.fileWatcherEnabled = fileWatcherEnabled
        }
        if let symbolsEnabled = launchConfig.symbolsEnabled {
            config.useSFSymbolsInTerminal = symbolsEnabled
        }
        if let mode = launchConfig.keybindingMode {
            config.keybindingMode =
                KittyConfig.KeybindingMode(rawValue: mode) ?? config.keybindingMode
        }
        if let tabSize = launchConfig.tabSize {
            config.editor.tabSize = tabSize
        }
        if let wrapLines = launchConfig.wrapLines {
            config.editor.wrapLines = wrapLines
        }
        if let hexFg = launchConfig.themeForeground,
            let color = ColorRGB(hex: hexFg.hasPrefix("#") ? hexFg : "#\(hexFg)")
        {
            config.theme.editorForeground = color
        }
    }
}

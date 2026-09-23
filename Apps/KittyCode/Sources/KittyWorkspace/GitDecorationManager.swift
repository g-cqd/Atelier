public import AemiCore
import AtelierText
public import KittyGit

public struct GitDecorationConfig: Sendable {
    public var showGitStatus: Bool
    public var showLineChanges: Bool
    public var lineChangeDebounceMilliseconds: UInt64
    public var maxLineDiffBytes: Int

    public init(
        showGitStatus: Bool,
        showLineChanges: Bool,
        lineChangeDebounceMilliseconds: UInt64,
        maxLineDiffBytes: Int
    ) {
        self.showGitStatus = showGitStatus
        self.showLineChanges = showLineChanges
        self.lineChangeDebounceMilliseconds = lineChangeDebounceMilliseconds
        self.maxLineDiffBytes = maxLineDiffBytes
    }
}

@MainActor
public final class GitDecorationManager {
    private let workspace: WorkspaceSession
    private let gitConfig: GitDecorationConfig
    private let gitLineDecorationProvider: (any GitLineDecorationProvider)?
    private let invalidateRender: @MainActor () -> Void
    private let taskProvider: any TaskProvider
    private let clock: any Clock<Duration>

    /// Debounced refresh requests: `bufferingNewest(1)` collapses a burst of keystrokes into one refresh after the
    /// debounce window.
    private let debouncedSignal: AsyncStream<Void>
    private let debouncedContinuation: AsyncStream<Void>.Continuation
    private var debouncedConsumer: Task<Void, Never>?

    /// The undelayed refresh of a tab switch or reload, separate so keystrokes can't fold it into a debounced one.
    private var immediateTask: Task<Void, Never>?

    public init(
        workspace: WorkspaceSession,
        gitConfig: GitDecorationConfig,
        gitLineDecorationProvider: (any GitLineDecorationProvider)?,
        invalidateRender: @MainActor @escaping () -> Void,
        taskProvider: any TaskProvider = .default,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.workspace = workspace
        self.gitConfig = gitConfig
        self.gitLineDecorationProvider = gitLineDecorationProvider
        self.invalidateRender = invalidateRender
        self.taskProvider = taskProvider
        self.clock = clock

        let (stream, cont) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.debouncedSignal = stream
        self.debouncedContinuation = cont

        let debounceMs = gitConfig.lineChangeDebounceMilliseconds
        self.debouncedConsumer = taskProvider.task(role: .observation) { [weak self, stream, clock] in
            for await _ in stream {
                try? await clock.sleep(for: .milliseconds(debounceMs))
                guard let self else { return }
                await self.performRefresh()
            }
        }
    }

    public func scheduleRefreshForActiveBuffer(debounced: Bool = true) {
        guard gitConfig.showGitStatus,
            gitConfig.showLineChanges,
            gitLineDecorationProvider != nil,
            let buffer = workspace.bufferManager.activeBuffer,
            !buffer.filePath.isEmpty
        else {
            clearActiveDecorations()
            return
        }
        _ = buffer  // capture-by-existence; performRefresh re-reads state

        if debounced {
            debouncedContinuation.yield(())
        } else {
            immediateTask?.cancel()
            immediateTask = taskProvider.task(role: .work) { [weak self] in
                guard let self else { return }
                await self.performRefresh()
            }
        }
    }

    /// Computes decorations from the active buffer's current state; `apply(_:for:version:)` drops them if the buffer
    /// has moved on meanwhile.
    private func performRefresh() async {
        guard gitConfig.showGitStatus,
            gitConfig.showLineChanges,
            let provider = gitLineDecorationProvider,
            let buffer = workspace.bufferManager.activeBuffer,
            !buffer.filePath.isEmpty
        else {
            return
        }

        let textBuffer = workspace.textBuffer
        let path = buffer.filePath
        let version = buffer.documentVersion
        let maxLineDiffBytes = gitConfig.maxLineDiffBytes

        // `byteCount` is cached on the rope, so the size gate needs no materialised lines.
        guard textBuffer.byteCount <= maxLineDiffBytes else {
            clearActiveDecorations(for: path, version: version)
            return
        }

        let lines = textBuffer.lines
        let decorations = await provider.lineDecorations(for: path, lines: lines)
        apply(decorations, for: path, version: version)
    }

    public func stop() {
        debouncedContinuation.finish()
        debouncedConsumer?.cancel()
        debouncedConsumer = nil
        immediateTask?.cancel()
        immediateTask = nil
    }

    private func apply(_ decorations: GitLineDecorations, for path: String, version: Int) {
        guard let buffer = workspace.bufferManager.activeBuffer,
            buffer.filePath == path,
            buffer.documentVersion == version
        else {
            return
        }

        buffer.gitLineDecorations = decorations
        invalidateRender()
    }

    private func clearActiveDecorations() {
        // A stale immediate refresh must not repopulate what is being cleared; queued debounced signals recheck the
        // config on entry.
        immediateTask?.cancel()
        immediateTask = nil

        guard let buffer = workspace.bufferManager.activeBuffer,
            !buffer.gitLineDecorations.isEmpty
        else {
            return
        }

        buffer.gitLineDecorations = .empty
        invalidateRender()
    }

    private func clearActiveDecorations(for path: String, version: Int) {
        guard let buffer = workspace.bufferManager.activeBuffer,
            buffer.filePath == path,
            buffer.documentVersion == version,
            !buffer.gitLineDecorations.isEmpty
        else {
            return
        }

        buffer.gitLineDecorations = .empty
        invalidateRender()
    }

    nonisolated private static func approximateDocumentByteCount(lines: [String]) -> Int {
        lines.reduce(into: max(0, lines.count - 1)) { count, line in
            count += line.utf8.count
        }
    }
}

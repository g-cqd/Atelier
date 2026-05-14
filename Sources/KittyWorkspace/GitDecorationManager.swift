import KittyGit
import KittyText

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

    /// Long-lived consumer that handles the debounced refresh path. The
    /// producer (`scheduleRefreshForActiveBuffer(debounced: true)`) just
    /// yields a tick into `debouncedSignal`; the consumer waits one
    /// `lineChangeDebounceMilliseconds` window per signal and then re-reads
    /// active-buffer state on the main actor to compute decorations.
    /// `bufferingNewest(1)` collapses bursts of keystrokes (the hot path)
    /// into a single work cycle.
    private let debouncedSignal: AsyncStream<Void>
    private let debouncedContinuation: AsyncStream<Void>.Continuation
    private var debouncedConsumer: Task<Void, Never>?

    /// One-shot task for the rare immediate refresh path (tab switch,
    /// external file reload). Kept separate from the debounced consumer so
    /// the tab-switch's "no delay" intent isn't accidentally coalesced into
    /// the debounced stream when keystrokes arrive in quick succession.
    private var immediateTask: Task<Void, Never>?

    public init(
        workspace: WorkspaceSession,
        gitConfig: GitDecorationConfig,
        gitLineDecorationProvider: (any GitLineDecorationProvider)?,
        invalidateRender: @MainActor @escaping () -> Void
    ) {
        self.workspace = workspace
        self.gitConfig = gitConfig
        self.gitLineDecorationProvider = gitLineDecorationProvider
        self.invalidateRender = invalidateRender

        let (stream, cont) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.debouncedSignal = stream
        self.debouncedContinuation = cont

        let debounceMs = gitConfig.lineChangeDebounceMilliseconds
        self.debouncedConsumer = Task { [weak self, stream] in
            for await _ in stream {
                try? await Task.sleep(for: .milliseconds(debounceMs))
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
            immediateTask = Task { [weak self] in
                guard let self else { return }
                await self.performRefresh()
            }
        }
    }

    /// Re-reads active-buffer state on the main actor and computes the
    /// decoration set. Safe to call from either the debounced consumer or
    /// the one-shot immediate task — both paths route through here, and
    /// the staleness gate inside `apply(_:for:version:)` rejects results
    /// that arrive after the buffer has moved on.
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

        // `Rope.byteCount` is O(1) (cached on the tree root); avoid
        // materialising `[String]` lines + summing UTF-8 lengths just to
        // perform the size gate. Lines are still materialised below for the
        // diff provider, but the cache will be warm by then.
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
        // Cancel any in-flight immediate refresh so a stale `apply` can't
        // re-populate decorations after we've explicitly cleared them.
        // (The debounced consumer's stream still drains older queued
        // signals harmlessly — `performRefresh` re-checks `gitConfig.show*`
        // guards on entry.)
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

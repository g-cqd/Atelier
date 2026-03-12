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
    private var task: Task<Void, Never>?

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
    }

    public func scheduleRefreshForActiveBuffer(debounced: Bool = true) {
        task?.cancel()

        guard gitConfig.showGitStatus,
            gitConfig.showLineChanges,
            let provider = gitLineDecorationProvider,
            let buffer = workspace.bufferManager.activeBuffer,
            !buffer.filePath.isEmpty
        else {
            clearActiveDecorations()
            return
        }

        let textBuffer = workspace.textBuffer
        let path = buffer.filePath
        let version = buffer.documentVersion
        let debounceMilliseconds = gitConfig.lineChangeDebounceMilliseconds
        let maxLineDiffBytes = gitConfig.maxLineDiffBytes

        task = Task { [weak self] in
            if debounced {
                try? await Task.sleep(for: .milliseconds(debounceMilliseconds))
            }
            guard !Task.isCancelled else { return }

            let lines = textBuffer.lines
            let documentByteCount = Self.approximateDocumentByteCount(lines: lines)
            guard documentByteCount <= maxLineDiffBytes else {
                self?.clearActiveDecorations(for: path, version: version)
                return
            }

            let decorations = await provider.lineDecorations(for: path, lines: lines)
            guard !Task.isCancelled else { return }

            self?.apply(decorations, for: path, version: version)
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
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
        task?.cancel()
        task = nil

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

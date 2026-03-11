import KittyGit

@MainActor
final class GitDecorationManager {
    private let state: EditorState
    private let refreshSource: RenderRefreshSource
    private var task: Task<Void, Never>?

    init(state: EditorState, refreshSource: RenderRefreshSource) {
        self.state = state
        self.refreshSource = refreshSource
    }

    func scheduleRefreshForActiveBuffer(debounced: Bool = true) {
        task?.cancel()

        guard state.config.showGitStatus,
              state.config.gitDecorations.showLineChanges,
              let provider = state.gitLineDecorationProvider,
              let buffer = state.bufferManager.activeBuffer,
              !buffer.filePath.isEmpty
        else {
            clearActiveDecorations()
            return
        }

        let textBuffer = state.textBuffer
        let path = buffer.filePath
        let version = buffer.documentVersion
        let debounceMilliseconds = state.config.gitDecorations.lineChangeDebounceMilliseconds
        let maxLineDiffBytes = state.config.gitDecorations.maxLineDiffBytes

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

    func stop() {
        task?.cancel()
        task = nil
    }

    private func apply(_ decorations: GitLineDecorations, for path: String, version: Int) {
        guard let buffer = state.bufferManager.activeBuffer,
              buffer.filePath == path,
              buffer.documentVersion == version
        else {
            return
        }

        buffer.gitLineDecorations = decorations
        refreshSource.invalidate()
    }

    private func clearActiveDecorations() {
        task?.cancel()
        task = nil

        guard let buffer = state.bufferManager.activeBuffer,
              !buffer.gitLineDecorations.isEmpty
        else {
            return
        }

        buffer.gitLineDecorations = .empty
        refreshSource.invalidate()
    }

    private func clearActiveDecorations(for path: String, version: Int) {
        guard let buffer = state.bufferManager.activeBuffer,
              buffer.filePath == path,
              buffer.documentVersion == version,
              !buffer.gitLineDecorations.isEmpty
        else {
            return
        }

        buffer.gitLineDecorations = .empty
        refreshSource.invalidate()
    }

    private nonisolated static func approximateDocumentByteCount(lines: [String]) -> Int {
        lines.reduce(into: max(0, lines.count - 1)) { count, line in
            count += line.utf8.count
        }
    }
}

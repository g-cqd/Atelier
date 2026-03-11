import Foundation

@MainActor
final class AutoSaveManager {
    private let state: EditorState
    private let fileWatcherIntegration: FileWatcherIntegration?
    private var task: Task<Void, Never>?

    init(state: EditorState, fileWatcherIntegration: FileWatcherIntegration? = nil) {
        self.state = state
        self.fileWatcherIntegration = fileWatcherIntegration
    }

    func start() {
        guard task == nil else { return }
        let interval = state.config.autoSaveInterval

        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                self?.saveAllDirtyBuffers()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func saveAllDirtyBuffers() {
        for buffer in state.bufferManager.buffers where buffer.isDirty {
            guard !buffer.filePath.isEmpty else { continue }

            // Suppress file watcher for this save
            fileWatcherIntegration?.suppressForSave(buffer.filePath)

            // If this is the active buffer, use the state's save path
            if buffer === state.bufferManager.activeBuffer {
                state.writeBufferToDisk()
            } else {
                // Save non-active buffer directly
                let content = buffer.textBuffer.text
                do {
                    try content.write(toFile: buffer.filePath, atomically: true, encoding: .utf8)
                    buffer.isDirty = false
                    buffer.lastModifiedDate = Date()
                } catch {
                    // Silent failure for auto-save of non-active buffers
                }
            }
        }
    }
}

import Foundation

@MainActor
public final class AutoSaveManager {
    private let workspace: WorkspaceSession
    private let fileWatcherIntegration: FileWatcherIntegration?
    private let autoSaveInterval: Double
    private let saveActiveBuffer: @MainActor () -> Void
    private var task: Task<Void, Never>?

    public init(
        workspace: WorkspaceSession,
        fileWatcherIntegration: FileWatcherIntegration?,
        autoSaveInterval: Double,
        saveActiveBuffer: @MainActor @escaping () -> Void
    ) {
        self.workspace = workspace
        self.fileWatcherIntegration = fileWatcherIntegration
        self.autoSaveInterval = autoSaveInterval
        self.saveActiveBuffer = saveActiveBuffer
    }

    public func start() {
        guard task == nil else { return }
        let interval = autoSaveInterval

        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                self?.saveAllDirtyBuffers()
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    private func saveAllDirtyBuffers() {
        let bufferManager = workspace.bufferManager
        for buffer in bufferManager.buffers where buffer.isDirty {
            guard !buffer.filePath.isEmpty else { continue }

            fileWatcherIntegration?.suppressForSave(buffer.filePath)

            if buffer === bufferManager.activeBuffer {
                saveActiveBuffer()
            } else {
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

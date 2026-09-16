public import AemiCore
import AtelierText
import Foundation

@MainActor
public final class AutoSaveManager {
    private let workspace: WorkspaceSession
    private let fileWatcherIntegration: FileWatcherIntegration?
    private let autoSaveInterval: Double
    private let saveActiveBuffer: @MainActor () -> Void
    private let taskProvider: any TaskProvider
    private let clock: any Clock<Duration>
    private var task: Task<Void, Never>?

    public init(
        workspace: WorkspaceSession,
        fileWatcherIntegration: FileWatcherIntegration?,
        autoSaveInterval: Double,
        saveActiveBuffer: @MainActor @escaping () -> Void,
        taskProvider: any TaskProvider = .default,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.workspace = workspace
        self.fileWatcherIntegration = fileWatcherIntegration
        self.autoSaveInterval = autoSaveInterval
        self.saveActiveBuffer = saveActiveBuffer
        self.taskProvider = taskProvider
        self.clock = clock
    }

    public func start() {
        guard task == nil else { return }
        let interval = autoSaveInterval
        let clock = clock

        task = taskProvider.task(role: .observation) { [weak self] in
            while !Task.isCancelled {
                try? await clock.sleep(for: .seconds(interval))
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
                // Hand the write off to a background task so a slow disk can't
                // stall the render loop. The buffer reference is captured but
                // only used on the main actor after the write completes; the
                // snapshot we serialize is value-typed and safe to send.
                let path = buffer.filePath
                let data = Data(buffer.textBuffer.text.utf8)
                taskProvider.detachedTask(role: .work, priority: .utility) { [weak buffer] in
                    let url = URL(fileURLWithPath: path)
                    do {
                        try data.write(to: url, options: [.atomic])
                    } catch {
                        return  // Silent failure for auto-save of non-active buffers
                    }
                    await MainActor.run {
                        guard let buffer else { return }
                        buffer.isDirty = false
                        buffer.lastModifiedDate = Date()
                    }
                }
            }
        }
    }
}

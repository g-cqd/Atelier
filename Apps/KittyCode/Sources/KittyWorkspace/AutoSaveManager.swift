public import AemiCore
import AtelierText
public import Foundation
import os

/// Runs one blocking disk write off the cooperative pool, the way the app's `BlockingOffloadPool.run` does, and
/// returns what the write returns: the file's modification date after it.
public typealias BlockingDiskWrite = @Sendable (_ write: @escaping @Sendable () throws -> Date?) async throws -> Date?

/// Saves every dirty buffer on an interval. The active buffer saves through the editor, the others in the background,
/// through the app's blocking pool.
@MainActor
public final class AutoSaveManager {
    private let workspace: WorkspaceSession
    private let fileWatcherIntegration: FileWatcherIntegration?
    private let autoSaveInterval: Double
    private let saveActiveBuffer: @MainActor () -> Void
    private let offloadDiskWrite: BlockingDiskWrite
    private let reportFailure: @MainActor (String) -> Void
    private let taskProvider: any TaskProvider
    private let clock: any Clock<Duration>
    private var task: Task<Void, Never>?

    private static let logger = Logger(subsystem: "com.kittytui", category: "autosave")

    /// - Parameters:
    ///   - workspace: Holds the buffers to save.
    ///   - fileWatcherIntegration: Suppresses the watcher's echo of each save and re-checks a file whose change
    ///     arrived during its background save; nil when the watcher is off.
    ///   - autoSaveInterval: Seconds between saves.
    ///   - saveActiveBuffer: Saves the active buffer through the editor, which holds its live text.
    ///   - offloadDiskWrite: Runs a background save's blocking write, on the app's `BlockingOffloadPool`.
    ///   - reportFailure: Shows a failed background save's message to the user.
    ///   - taskProvider: Spawns the save loop and each background save.
    ///   - clock: Drives the interval.
    public init(
        workspace: WorkspaceSession,
        fileWatcherIntegration: FileWatcherIntegration?,
        autoSaveInterval: Double,
        saveActiveBuffer: @MainActor @escaping () -> Void,
        offloadDiskWrite: @escaping BlockingDiskWrite,
        reportFailure: @MainActor @escaping (String) -> Void,
        taskProvider: any TaskProvider = .default,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.workspace = workspace
        self.fileWatcherIntegration = fileWatcherIntegration
        self.autoSaveInterval = autoSaveInterval
        self.saveActiveBuffer = saveActiveBuffer
        self.offloadDiskWrite = offloadDiskWrite
        self.reportFailure = reportFailure
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

    /// What one background save wrote, to record on its buffer once the write lands.
    private struct BackgroundSave {
        let path: String
        let version: Int
        let dateBeforeSave: Date?
        let saved: BufferEditSnapshot
    }

    /// Saves each dirty buffer that has a file, except one still being written, and one whose file changed on disk
    /// since the buffer last read or wrote it: that change stays until the user overwrites it or reloads.
    func saveAllDirtyBuffers() {
        let bufferManager = workspace.bufferManager
        for buffer in bufferManager.buffers where buffer.isDirty && !buffer.filePath.isEmpty {
            guard !buffer.isSavingInBackground, !buffer.conflictsWithDisk() else { continue }
            if buffer === bufferManager.activeBuffer {
                saveActiveBuffer()
            } else {
                saveInBackground(buffer)
            }
        }
    }

    /// Writes `buffer`'s text, in its own line ending, on the blocking pool, so a slow disk cannot stall rendering;
    /// the buffer is updated back on the main actor, even if this manager is gone by then.
    private func saveInBackground(_ buffer: DocumentBuffer) {
        let save = BackgroundSave(
            path: buffer.filePath, version: buffer.documentVersion, dateBeforeSave: buffer.lastModifiedDate,
            saved: BufferEditSnapshot(
                textBuffer: buffer.textBuffer, textCursor: buffer.textCursor, lineEnding: buffer.lineEnding))
        let data = Data(TextDocument.serializedText(from: buffer.textBuffer.text, lineEnding: buffer.lineEnding).utf8)
        let path = save.path
        let offloadDiskWrite = offloadDiskWrite
        let integration = fileWatcherIntegration
        let reportFailure = reportFailure
        integration?.suppressForSave(path)
        buffer.isSavingInBackground = true

        taskProvider.task(role: .work) { [weak buffer] in
            let outcome: Result<Date?, any Error>
            do {
                outcome = .success(try await offloadDiskWrite { try Self.writeAtomically(data, to: path) })
            } catch {
                outcome = .failure(error)
            }
            guard let buffer else { return }
            await Self.finish(
                save, of: buffer, outcome: outcome, integration: integration, reportFailure: reportFailure)
        }
    }

    /// Records a background save's outcome on `buffer`. The buffer counts as saved only if nothing changed it while
    /// its file was written; the new modification date is kept unless a save or reload recorded its own meanwhile.
    private static func finish(
        _ save: BackgroundSave, of buffer: DocumentBuffer, outcome: Result<Date?, any Error>,
        integration: FileWatcherIntegration?, reportFailure: @MainActor (String) -> Void
    ) async {
        buffer.isSavingInBackground = false
        switch outcome {
            case .success(let diskDate):
                if buffer.filePath == save.path, buffer.lastModifiedDate == save.dateBeforeSave {
                    buffer.lastModifiedDate = diskDate
                    buffer.externallyModified = false
                }
                if buffer.documentVersion == save.version {
                    buffer.editHistory.markSaved(save.saved)
                    buffer.isDirty = false
                }
            case .failure(let error):
                logger.error("Autosave failed: \(error.localizedDescription, privacy: .private)")
                reportFailure("Autosave failed for \(buffer.fileName): \(error.localizedDescription)")
        }
        guard buffer.hasDiskCheckPending else { return }
        buffer.hasDiskCheckPending = false
        await integration?.reconcileWithDisk(buffer)
    }

    /// Writes `data` over the file at `path` atomically.
    /// - Returns: The file's modification date after the write, or nil when it cannot be read back.
    nonisolated static func writeAtomically(_ data: Data, to path: String) throws -> Date? {
        try data.write(to: URL(fileURLWithPath: path), options: [.atomic])
        return WorkspaceFileLoading.modificationDate(ofFileAt: path)
    }
}

public import AemiCore
import AtelierText
import Foundation
public import KittyFileTree
import os

/// The watcher calls the workspace makes, as a protocol so a test can inject a synthetic source.
public protocol FileWatching: Sendable {
    var events: AsyncStream<FileWatcher.FileWatchEvent> { get }
    func watchDirectory(_ path: String) async
    func watchFile(_ path: String) async
    func unwatchFile(_ path: String) async
    func suppressNotifications(for path: String)
    func stop() async
}

extension FileWatcher: FileWatching {}

@MainActor
public protocol FileWatcherDelegate: AnyObject {
    func fileWatcherDidDetectDirectoryChange() async
    func fileWatcherDidDetectExternalModification(bufferName: String)
    /// `replaced` is what the buffer let go of, for the delegate to free off the main actor.
    func fileWatcherDidReloadActiveBuffer(
        buffer: DocumentBuffer, content: String, replaced: consuming DocumentBuffer.ReplacedContents)
    /// `replaced` is what the buffer let go of, for the delegate to free off the main actor.
    func fileWatcherDidReloadInactiveBuffer(
        buffer: DocumentBuffer, content: String, replaced: consuming DocumentBuffer.ReplacedContents)
}

/// Keeps the open buffers in step with their files: the workspace's directory and every open file are watched, a
/// clean buffer reloads when its file changes, and a dirty one is flagged as externally modified.
@MainActor
public final class FileWatcherIntegration {
    private let watcher: any FileWatching
    private let workspace: WorkspaceSession
    private weak var delegate: (any FileWatcherDelegate)?
    private let taskProvider: any TaskProvider
    /// Runs the blocking read of a file that changed, on the app's pool.
    private let offloadFileRead: BlockingFileRead
    private var watchTask: Task<Void, Never>?
    /// The canonical paths each watched file's events can arrive under, keyed by the buffer's own path.
    private var canonicalPaths: [String: [String]] = [:]

    private static let logger = Logger(subsystem: "com.kittytui", category: "file-watcher")

    /// - Parameters:
    ///   - watcher: Reports changes to the workspace's directory and its open files.
    ///   - workspace: Holds the buffers kept in step with their files.
    ///   - delegate: Hears of every reload, flag and directory change.
    ///   - offloadFileRead: Runs the blocking read of a file that changed, on the app's `BlockingOffloadPool`.
    ///   - taskProvider: Runs the loop that reads the watcher's events.
    public init(
        watcher: any FileWatching, workspace: WorkspaceSession, delegate: any FileWatcherDelegate,
        offloadFileRead: @escaping BlockingFileRead, taskProvider: any TaskProvider = .default
    ) {
        self.watcher = watcher
        self.workspace = workspace
        self.delegate = delegate
        self.offloadFileRead = offloadFileRead
        self.taskProvider = taskProvider
    }

    public func start() {
        let watcher = watcher
        let rootPath = workspace.rootPath
        taskProvider.task(role: .work) { await watcher.watchDirectory(rootPath) }

        for buffer in workspace.bufferManager.buffers {
            watchOpenedFile(buffer.filePath)
        }

        let events = watcher.events
        watchTask = taskProvider.task(role: .observation) { [weak self] in
            for await event in events {
                guard let self else { return }
                await self.handleEvent(event)
            }
        }
    }

    public func stop() {
        watchTask?.cancel()
        watchTask = nil
        let watcher = watcher
        taskProvider.task(role: .work) { await watcher.stop() }
    }

    public func watchOpenedFile(_ path: String) {
        canonicalPaths[path] = FileWatcher.canonicalPaths(forFile: path)
        let watcher = watcher
        taskProvider.task(role: .work) { await watcher.watchFile(path) }
    }

    public func unwatchClosedFile(_ path: String) {
        canonicalPaths[path] = nil
        let watcher = watcher
        taskProvider.task(role: .work) { await watcher.unwatchFile(path) }
    }

    public func suppressForSave(_ path: String) {
        // Synchronous and lock-based on the watcher side — no task needed to cross isolation.
        watcher.suppressNotifications(for: path)
    }

    /// Brings `buffer` in line with its file after the file may have changed: a clean buffer reloads, a dirty one is
    /// flagged as externally modified, and a file whose modification date is the one the buffer last read or wrote is
    /// left alone, which is how the editor's own saves pass. While a background save writes the file, the check waits
    /// for it: ``DocumentBuffer/hasDiskCheckPending`` asks its writer to call this again once it lands.
    public func reconcileWithDisk(_ buffer: DocumentBuffer) async {
        guard !buffer.isSavingInBackground else {
            buffer.hasDiskCheckPending = true
            return
        }
        let path = buffer.filePath
        guard let diskDate = WorkspaceFileLoading.modificationDate(ofFileAt: path),
            diskDate != buffer.lastModifiedDate
        else { return }
        guard !buffer.isDirty else {
            flagExternalModification(of: buffer)
            return
        }

        let version = buffer.documentVersion
        let loadedFile: LoadedFile
        do {
            loadedFile = try await WorkspaceFileLoading.readUTF8File(at: path, offload: offloadFileRead)
        } catch {
            Self.logger.error("Reloading a changed file failed: \(error.localizedDescription, privacy: .private)")
            return
        }
        // An edit, save or reload that landed during the read wins: reloading now would discard it.
        guard buffer.documentVersion == version, buffer.filePath == path, !buffer.isSavingInBackground else {
            if buffer.isDirty {
                flagExternalModification(of: buffer)
            }
            return
        }
        guard let index = workspace.bufferManager.buffers.firstIndex(where: { $0 === buffer }) else { return }
        let isActive = index == workspace.bufferManager.activeIndex
        if isActive {
            // The live cursor sits in the workspace; the reload clamps it, not the buffer's stale copy.
            workspace.saveStateToActiveBuffer()
        }

        let replaced = buffer.replaceContents(with: loadedFile, modifiedAt: diskDate)
        buffer.didInvalidateHistoryOnLastRefresh = buffer.editHistory.reconcileWithRefresh(
            BufferEditSnapshot(
                textBuffer: buffer.textBuffer,
                textCursor: buffer.textCursor,
                lineEnding: buffer.lineEnding
            )
        )
        guard let delegate else { return }
        if isActive {
            delegate.fileWatcherDidReloadActiveBuffer(
                buffer: buffer, content: loadedFile.content, replaced: consume replaced)
        } else {
            delegate.fileWatcherDidReloadInactiveBuffer(
                buffer: buffer, content: loadedFile.content, replaced: consume replaced)
        }
    }

    private func handleEvent(_ event: FileWatcher.FileWatchEvent) async {
        switch event {
            case .fileChanged(let path):
                await reconcileBuffers(at: path)
            case .directoryChanged(let path):
                // FSEvents reports canonical paths, so an open file can surface here, as `/private/tmp/...` for a buffer
                // opened as `/tmp/...`.
                await reconcileBuffers(at: path)
                await delegate?.fileWatcherDidDetectDirectoryChange()
        }
    }

    /// Reconciles each open buffer whose file `path` names, in the buffer's own spelling or a canonical one.
    private func reconcileBuffers(at path: String) async {
        let matches = workspace.bufferManager.buffers.filter { buffer in
            buffer.filePath == path || canonicalPaths[buffer.filePath]?.contains(path) == true
        }
        for buffer in matches {
            await reconcileWithDisk(buffer)
        }
    }

    private func flagExternalModification(of buffer: DocumentBuffer) {
        buffer.externallyModified = true
        if buffer === workspace.bufferManager.activeBuffer {
            delegate?.fileWatcherDidDetectExternalModification(bufferName: buffer.fileName)
        }
    }
}

/// Calls back whenever one file changes on disk, however it was saved: written in place, or replaced by another
/// editor's atomic save, which renames a new file over it. The app watches its configuration file with one.
@MainActor
public final class WatchedFileMonitor {
    private let path: String
    private let canonicalPaths: Set<String>
    private let watcher: any FileWatching
    private let taskProvider: any TaskProvider
    private let onChange: @MainActor () -> Void
    private var watchTask: Task<Void, Never>?

    /// - Parameters:
    ///   - path: The file to watch.
    ///   - watcher: A watcher this monitor owns: ``stop()`` stops it.
    ///   - taskProvider: Runs the loop that reads the watcher's events.
    ///   - onChange: Runs on the main actor after each change to the file.
    public init(
        path: String, watcher: any FileWatching, taskProvider: any TaskProvider = .default,
        onChange: @escaping @MainActor () -> Void
    ) {
        self.path = path
        self.canonicalPaths = Set(FileWatcher.canonicalPaths(forFile: path))
        self.watcher = watcher
        self.taskProvider = taskProvider
        self.onChange = onChange
    }

    /// Starts watching; changes after this returns reach `onChange`.
    public func start() async {
        await watcher.watchFile(path)
        let events = watcher.events
        watchTask = taskProvider.task(role: .observation) { [weak self] in
            for await event in events {
                guard let self else { return }
                if self.concerns(event) {
                    self.onChange()
                }
            }
        }
    }

    /// Stops watching; `onChange` runs no more.
    public func stop() async {
        watchTask?.cancel()
        watchTask = nil
        await watcher.stop()
    }

    /// Whether `event` reports the watched file, under its own path or a canonical one.
    func concerns(_ event: FileWatcher.FileWatchEvent) -> Bool {
        switch event {
            case .fileChanged(let changed):
                changed == path || canonicalPaths.contains(changed)
            case .directoryChanged(let changed):
                canonicalPaths.contains(changed)
        }
    }
}

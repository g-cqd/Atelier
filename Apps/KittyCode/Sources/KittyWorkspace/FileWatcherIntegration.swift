import AtelierText
import Foundation
public import KittyFileTree

@MainActor
public protocol FileWatcherDelegate: AnyObject {
    func fileWatcherDidDetectDirectoryChange() async
    func fileWatcherDidDetectExternalModification(bufferName: String)
    func fileWatcherDidReloadActiveBuffer(buffer: DocumentBuffer, content: String)
    func fileWatcherDidReloadInactiveBuffer(buffer: DocumentBuffer, content: String)
}

@MainActor
public final class FileWatcherIntegration {
    private let watcher: FileWatcher
    private let workspace: WorkspaceSession
    private weak var delegate: (any FileWatcherDelegate)?
    private var watchTask: Task<Void, Never>?

    public init(watcher: FileWatcher, workspace: WorkspaceSession, delegate: any FileWatcherDelegate) {
        self.watcher = watcher
        self.workspace = workspace
        self.delegate = delegate
    }

    public func start() {
        Task { await watcher.watchDirectory(workspace.rootPath) }

        for buffer in workspace.bufferManager.buffers {
            Task { await watcher.watchFile(buffer.filePath) }
        }

        watchTask = Task { [weak self] in
            guard let self else { return }
            for await event in self.watcher.events {
                await self.handleEvent(event)
            }
        }
    }

    public func stop() {
        watchTask?.cancel()
        watchTask = nil
        Task { await watcher.stop() }
    }

    public func watchOpenedFile(_ path: String) {
        Task { await watcher.watchFile(path) }
    }

    public func unwatchClosedFile(_ path: String) {
        Task { await watcher.unwatchFile(path) }
    }

    public func suppressForSave(_ path: String) {
        Task { await watcher.suppressNotifications(for: path) }
    }

    private func handleEvent(_ event: FileWatcher.FileWatchEvent) async {
        switch event {
            case .fileChanged(let path):
                await handleFileChanged(path)
            case .directoryChanged:
                await delegate?.fileWatcherDidDetectDirectoryChange()
        }
    }

    private func handleFileChanged(_ path: String) async {
        let bufferManager = workspace.bufferManager
        guard let index = bufferManager.bufferIndex(forPath: path) else { return }
        let buffer = bufferManager.buffers[index]

        let url = URL(fileURLWithPath: path)
        guard
            let diskDate = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                .contentModificationDate
        else { return }

        if let lastMod = buffer.lastModifiedDate, diskDate <= lastMod {
            return
        }

        if buffer.isDirty {
            buffer.externallyModified = true
            if index == bufferManager.activeIndex {
                delegate?.fileWatcherDidDetectExternalModification(bufferName: buffer.fileName)
            }
        } else {
            guard let loadedFile = try? await WorkspaceFileLoading.readUTF8File(at: path) else {
                return
            }
            let content = loadedFile.content

            buffer.postOpenProcessingTask?.cancel()
            buffer.postOpenProcessingTask = nil
            buffer.textBuffer = TextBuffer(content)
            buffer.lineEnding = loadedFile.lineEnding
            buffer.lastModifiedDate = diskDate
            buffer.selection = nil
            buffer.highlightedLines = []
            buffer.highlightSession = nil
            buffer.cachedFileLines = nil
            buffer.cachedDocumentText = nil
            buffer.cachedMaxLineWidth = nil
            buffer.cachedSerializedByteCount = nil
            buffer.documentVersion += 1
            buffer.didInvalidateHistoryOnLastRefresh = buffer.editHistory.reconcileWithRefresh(
                BufferEditSnapshot(
                    textBuffer: buffer.textBuffer,
                    textCursor: buffer.textCursor,
                    lineEnding: buffer.lineEnding
                )
            )

            let lineCount = buffer.textBuffer.lineCount
            buffer.textCursor.row = min(buffer.textCursor.row, max(0, lineCount - 1))
            let lineLength = buffer.textBuffer.line(at: buffer.textCursor.row).count
            buffer.textCursor.col = min(buffer.textCursor.col, lineLength)
            buffer.textCursor.scrollRow = min(buffer.textCursor.scrollRow, max(0, lineCount - 1))

            if index == bufferManager.activeIndex {
                delegate?.fileWatcherDidReloadActiveBuffer(buffer: buffer, content: content)
            } else {
                delegate?.fileWatcherDidReloadInactiveBuffer(buffer: buffer, content: content)
            }
        }
    }
}

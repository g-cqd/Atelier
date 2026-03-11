import Foundation
import KittyFileTree
import KittyText

@MainActor
final class FileWatcherIntegration {
    private let watcher: FileWatcher
    private let state: EditorState
    private var watchTask: Task<Void, Never>?

    init(watcher: FileWatcher, state: EditorState) {
        self.watcher = watcher
        self.state = state
    }

    func start() {
        Task { await watcher.watchDirectory(state.rootPath) }

        // Watch all currently open files
        for buffer in state.bufferManager.buffers {
            Task { await watcher.watchFile(buffer.filePath) }
        }

        watchTask = Task { [weak self] in
            guard let self else { return }
            for await event in self.watcher.events {
                await self.handleEvent(event)
            }
        }
    }

    func stop() {
        watchTask?.cancel()
        watchTask = nil
        Task { await watcher.stop() }
    }

    func watchOpenedFile(_ path: String) {
        Task { await watcher.watchFile(path) }
    }

    func unwatchClosedFile(_ path: String) {
        Task { await watcher.unwatchFile(path) }
    }

    func suppressForSave(_ path: String) {
        Task { await watcher.suppressNotifications(for: path) }
    }

    private func handleEvent(_ event: FileWatcher.FileWatchEvent) async {
        switch event {
        case .fileChanged(let path):
            await handleFileChanged(path)
        case .directoryChanged:
            await state.loadInitialTree()
        }
    }

    private func handleFileChanged(_ path: String) async {
        guard let index = state.bufferManager.bufferIndex(forPath: path) else { return }
        let buffer = state.bufferManager.buffers[index]

        // Check if file actually changed on disk
        let fileManager = FileManager.default
        guard let attrs = try? fileManager.attributesOfItem(atPath: path),
              let diskDate = attrs[.modificationDate] as? Date else { return }

        if let lastMod = buffer.lastModifiedDate, diskDate <= lastMod {
            return
        }

        if buffer.isDirty {
            buffer.externallyModified = true
            if index == state.bufferManager.activeIndex {
                state.statusMessage = "\(buffer.fileName) changed on disk (unsaved changes)"
            }
        } else {
            // Auto-reload clean buffer
            guard let data = fileManager.contents(atPath: path),
                  let content = String(data: data, encoding: .utf8) else { return }

            buffer.textBuffer = TextBuffer(content)
            buffer.lastModifiedDate = diskDate
            buffer.highlightSession = nil
            buffer.cachedFileLines = nil
            buffer.cachedDocumentText = nil
            buffer.documentVersion += 1

            // Clamp cursor to valid bounds instead of resetting
            let lineCount = buffer.textBuffer.lineCount
            buffer.textCursor.row = min(buffer.textCursor.row, max(0, lineCount - 1))
            let lineLength = buffer.textBuffer.line(at: buffer.textCursor.row).count
            buffer.textCursor.col = min(buffer.textCursor.col, lineLength)
            buffer.textCursor.scrollRow = min(buffer.textCursor.scrollRow, max(0, lineCount - 1))

            if index == state.bufferManager.activeIndex {
                state.restoreStateFromActiveBuffer()
                state.refreshHighlights()
                state.gitDecorationManager?.scheduleRefreshForActiveBuffer(debounced: false)
                state.renderRefreshSource?.invalidate()
                state.statusMessage = "\(buffer.fileName) reloaded from disk"
            }
        }
    }
}

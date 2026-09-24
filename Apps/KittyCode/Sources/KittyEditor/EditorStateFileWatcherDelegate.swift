import AemiCore
import Foundation
import KittyApp
public import KittyWorkspace

import struct KittySyntax.LineHighlights

extension EditorState: FileWatcherDelegate {
    public func fileWatcherDidDetectDirectoryChange() async {
        await loadInitialTree()
    }

    public func fileWatcherDidDetectExternalModification(bufferName: String) {
        statusMessage = "\(bufferName) changed on disk (unsaved changes)"
    }

    public func fileWatcherDidReloadActiveBuffer(
        buffer: DocumentBuffer, content: String, replaced: consuming DocumentBuffer.ReplacedContents
    ) {
        // The old text's highlights and caches, which the buffer no longer holds, retired once replaced, below.
        let retired = activeDocumentStorage(replaced: consume replaced)
        // The workspace's restore, not the state's, whose refresh this would clear at once: the post-load pass below
        // highlights and measures the new text, as it does after an open.
        workspace.restoreStateFromActiveBuffer()
        highlightedLines = []
        invalidateHighlightSession()
        isLoadingGrammar = false
        gitDecorationManager?.scheduleRefreshForActiveBuffer(debounced: false)
        schedulePostLoadProcessing(for: buffer, content: content)
        // External reload: buffer contents, gutter, and highlights all change.
        markEverythingDirty()
        renderRefreshSource?.invalidate()
        if buffer.didInvalidateHistoryOnLastRefresh {
            statusMessage = "\(buffer.fileName) reloaded from disk; undo history cleared"
        } else {
            statusMessage = "\(buffer.fileName) reloaded from disk"
        }
        retire(consume retired)
    }

    public func fileWatcherDidReloadInactiveBuffer(
        buffer: DocumentBuffer, content: String, replaced: consuming DocumentBuffer.ReplacedContents
    ) {
        schedulePostLoadProcessing(for: buffer, content: content)
        // The only reference left to the old text's highlights, which an inactive tab an open left behind still holds.
        retire(RetiredStorage(replaced: consume replaced))
    }
}

extension EditorState {
    /// Replaces the active buffer's text with its file's, discarding unsaved edits: `:e!` and the reload command. The
    /// reload is one undo step, so undo brings the edits back, unsaved against the file.
    public func reloadActiveBufferFromDisk() {
        guard let buffer = bufferManager.activeBuffer, !buffer.filePath.isEmpty else {
            statusMessage = "No file to reload"
            return
        }
        guard !buffer.isSavingInBackground else {
            statusMessage = "\(buffer.fileName) is being autosaved: reload again in a moment"
            return
        }
        taskProvider.task(role: .work) { [weak self, weak buffer, offloadFileRead] in
            guard let self, let buffer else { return }
            do {
                // While the buffer is active its live text and cursor sit in the workspace: the undo step starts there.
                let reloaded = try await buffer.reloadFromDisk(offloadFileRead: offloadFileRead) {
                    if self.bufferManager.activeBuffer === buffer { self.saveStateToActiveBuffer() }
                }
                // What the buffer let go of goes to the state's consumer, which must hold its last reference.
                switch consume reloaded {
                    case (let file, let replaced)? where self.bufferManager.activeBuffer === buffer:
                        self.fileWatcherDidReloadActiveBuffer(
                            buffer: buffer, content: file.content, replaced: consume replaced)
                    case (let file, let replaced)?:
                        self.fileWatcherDidReloadInactiveBuffer(
                            buffer: buffer, content: file.content, replaced: consume replaced)
                    case nil:
                        self.statusMessage = "\(buffer.fileName) changed while reloading: reload again to discard it"
                }
            } catch {
                self.statusMessage = "Cannot reload \(buffer.fileName): \(error.localizedDescription)"
            }
            self.renderRefreshSource?.invalidate()
        }
    }
}

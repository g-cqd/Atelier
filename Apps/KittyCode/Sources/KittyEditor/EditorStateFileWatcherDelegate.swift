import KittyApp
public import KittyWorkspace

extension EditorState: FileWatcherDelegate {
    public func fileWatcherDidDetectDirectoryChange() async {
        await loadInitialTree()
    }

    public func fileWatcherDidDetectExternalModification(bufferName: String) {
        statusMessage = "\(bufferName) changed on disk (unsaved changes)"
    }

    public func fileWatcherDidReloadActiveBuffer(buffer: DocumentBuffer, content: String) {
        // The old text's highlights and caches, which the buffer no longer holds, retired once replaced, below.
        let retired = activeDocumentStorage()
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

    public func fileWatcherDidReloadInactiveBuffer(buffer: DocumentBuffer, content: String) {
        schedulePostLoadProcessing(for: buffer, content: content)
    }
}

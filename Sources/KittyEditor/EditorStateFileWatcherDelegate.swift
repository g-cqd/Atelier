import KittyWorkspace

extension EditorState: FileWatcherDelegate {
    public func fileWatcherDidDetectDirectoryChange() async {
        await loadInitialTree()
    }

    public func fileWatcherDidDetectExternalModification(bufferName: String) {
        statusMessage = "\(bufferName) changed on disk (unsaved changes)"
    }

    public func fileWatcherDidReloadActiveBuffer(buffer: DocumentBuffer, content: String) {
        restoreStateFromActiveBuffer()
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
    }

    public func fileWatcherDidReloadInactiveBuffer(buffer: DocumentBuffer, content: String) {
        schedulePostLoadProcessing(for: buffer, content: content)
    }
}

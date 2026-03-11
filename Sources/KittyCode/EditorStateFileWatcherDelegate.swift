import KittyWorkspace

extension EditorState: FileWatcherDelegate {
    func fileWatcherDidDetectDirectoryChange() async {
        await loadInitialTree()
    }

    func fileWatcherDidDetectExternalModification(bufferName: String) {
        statusMessage = "\(bufferName) changed on disk (unsaved changes)"
    }

    func fileWatcherDidReloadActiveBuffer(buffer: DocumentBuffer, content: String) {
        restoreStateFromActiveBuffer()
        highlightedLines = []
        invalidateHighlightSession()
        isLoadingGrammar = false
        gitDecorationManager?.scheduleRefreshForActiveBuffer(debounced: false)
        schedulePostLoadProcessing(for: buffer, content: content)
        renderRefreshSource?.invalidate()
        statusMessage = "\(buffer.fileName) reloaded from disk"
    }

    func fileWatcherDidReloadInactiveBuffer(buffer: DocumentBuffer, content: String) {
        schedulePostLoadProcessing(for: buffer, content: content)
    }
}

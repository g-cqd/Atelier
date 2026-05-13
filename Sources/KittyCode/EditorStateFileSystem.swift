import Foundation
import KittyFileTree
import KittySyntax
import KittyText
import KittyWorkspace

extension EditorState {

    func loadInitialTree(validateHistory: Bool = true) async {
        let expandedPaths = collectExpandedPaths(treeNodes)
        treeNodes = await DirectoryScanner.scanAsync(
            rootPath, maxDepth: 1, visibility: fileVisibility)
        if !expandedPaths.isEmpty {
            restoreExpandedPaths(expandedPaths, in: &treeNodes)
        }
        refreshFlatTree()
        if validateHistory, fileTreeHistory.validateRefresh(with: treeNodes) {
            statusMessage = "File history cleared after tree refresh"
        }

        // Clamp scroll/selection to valid range after rescan
        let maxIndex = max(0, cachedFlatTree.count - 1)
        treeScrollOffset = min(treeScrollOffset, maxIndex)
        selectedTreeIndex = min(selectedTreeIndex, maxIndex)
    }

    private func collectExpandedPaths(_ nodes: [FileNode]) -> Set<String> {
        var paths = Set<String>()
        for node in nodes {
            if node.isDirectory && node.isExpanded {
                paths.insert(node.path)
                paths.formUnion(collectExpandedPaths(node.children))
            }
        }
        return paths
    }

    private func restoreExpandedPaths(_ paths: Set<String>, in nodes: inout [FileNode]) {
        for i in nodes.indices {
            if nodes[i].isDirectory && paths.contains(nodes[i].path) {
                if !nodes[i].isExpanded {
                    FileTreeNavigator.toggleExpand(
                        in: &nodes, at: nodes[i].path, visibility: fileVisibility)
                }
                if !nodes[i].children.isEmpty {
                    restoreExpandedPaths(paths, in: &nodes[i].children)
                }
            }
        }
    }

    func refreshFlatTree() {
        cachedFlatTree = FileTreeNavigator.flatten(treeNodes)
        // Clamp scroll/selection to valid range
        let maxIndex = max(0, cachedFlatTree.count - 1)
        treeScrollOffset = min(treeScrollOffset, maxIndex)
        selectedTreeIndex = min(selectedTreeIndex, maxIndex)
        prewarmVisibleSyntaxArtifacts()
    }

    func toggleExpand(at index: Int) {
        let flat = cachedFlatTree
        guard index < flat.count else { return }
        let node = flat[index].node
        guard node.isDirectory else { return }
        FileTreeNavigator.toggleExpand(in: &treeNodes, at: node.path, visibility: fileVisibility)
        refreshFlatTree()
    }

    func openFile(at index: Int) {
        let flat = cachedFlatTree
        guard index < flat.count else { return }
        let node = flat[index].node
        guard !node.isDirectory else { return }

        noteSelectedPath(node.path, isDirectory: false)
        openFilePath(node.path, name: node.name)
    }

    func openFileByPath(_ path: String) {
        let name = (path as NSString).lastPathComponent
        openFilePath(path, name: name)
    }

    func openFilePath(_ path: String, name: String) {
        // Path traversal protection
        guard SecurePath.isValid(path, root: rootPath) else {
            statusMessage = "Access denied: path outside project root"
            return
        }

        let requestID = nextOpenRequestID()
        cancelPendingFileOpen()

        // If already open, just switch to it
        if let existingIndex = bufferManager.bufferIndex(forPath: path) {
            if existingIndex != bufferManager.activeIndex {
                switchToTab(existingIndex)
            }
            gitDecorationManager?.scheduleRefreshForActiveBuffer(debounced: false)
            mode = .editor
            let resolver = KeymapResolver(config: config)
            statusMessage = "Opened \(name) | \(resolver.openedStatusHints())"
            if config.keybindingMode == .vim {
                vimMode = .normal
                statusMessage = "-- NORMAL -- [\(name)] :w=Save, :q=Quit"
            }
            return
        }

        let fileManager = FileManager.default
        let attributes = try? fileManager.attributesOfItem(atPath: path)
        if let fileSize = attributes?[.size] as? Int,
            fileSize > WorkspaceFileLoading.maxFileSize
        {
            statusMessage =
                "File too large (\(fileSize / 1_000_000)MB, limit \(WorkspaceFileLoading.maxFileSize / 1_000_000)MB)"
            return
        }

        // Save current buffer state before switching
        saveStateToActiveBuffer()

        let language = Self.detectLanguage(for: name)
        let modDate = attributes?[.modificationDate] as? Date
        statusMessage = "Opening \(name)..."
        renderRefreshSource?.invalidate()

        let task = Task { [weak self] in
            guard let self else { return }

            do {
                let loadedFile = try await WorkspaceFileLoading.readUTF8File(at: path)
                guard !Task.isCancelled else { return }
                guard self.isCurrentOpenRequest(requestID) else { return }

                self.finishOpeningFile(
                    requestID: requestID,
                    path: path,
                    name: name,
                    content: loadedFile.content,
                    language: language,
                    modificationDate: modDate,
                    lineEnding: loadedFile.lineEnding
                )
            } catch {
                guard self.isCurrentOpenRequest(requestID) else { return }
                self.statusMessage = "Cannot read: \(name)"
                self.renderRefreshSource?.invalidate()
            }
        }
        replaceFileOpenTask(with: task)
    }

    /// Detect language name from file extension.
    static func detectLanguage(for filename: String) -> String? {
        LanguageHighlighter.detectLanguage(for: filename)
    }

    func saveFile() {
        if bufferManager.activeBuffer == nil {
            beginNewFile()
        }

        if filePath.isEmpty {
            beginSavePrompt()
            return
        }

        _ = writeBufferToDisk(at: filePath)
    }

    @discardableResult
    func writeBufferToDisk(at destinationPath: String) -> Bool {
        guard !readOnly else {
            statusMessage = "Read-only mode"
            return false
        }
        guard !destinationPath.isEmpty else {
            statusMessage = "Path required"
            return false
        }

        guard let activeBuffer = bufferManager.activeBuffer else {
            statusMessage = "No active buffer"
            return false
        }

        guard SecurePath.isValid(destinationPath, root: rootPath) else {
            statusMessage = "Access denied: cannot save outside project root"
            return false
        }

        if let existingIndex = bufferManager.bufferIndex(forPath: destinationPath),
            existingIndex != bufferManager.activeIndex
        {
            statusMessage =
                "Already open: \(URL(fileURLWithPath: destinationPath).lastPathComponent)"
            return false
        }

        let targetURL = URL(fileURLWithPath: destinationPath)
        let targetDirectory = targetURL.deletingLastPathComponent()
        let previousPath = activeBuffer.filePath
        let previousName = activeBuffer.fileName
        let previousLanguage = activeBuffer.language
        let content = TextDocument.serializedText(from: documentText, lineEnding: currentLineEnding)

        do {
            try FileManager.default.createDirectory(
                at: targetDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
            fileWatcherIntegration?.suppressForSave(destinationPath)
            try content.write(to: targetURL, atomically: true, encoding: .utf8)

            let savedDate = Date()
            let savedName = targetURL.lastPathComponent
            let savedLanguage = Self.detectLanguage(for: savedName)

            filePath = destinationPath
            fileName = savedName
            currentLanguage = savedLanguage
            noteSelectedPath(targetDirectory.path, isDirectory: true)

            if previousLanguage != savedLanguage {
                invalidateHighlightSession()
                refreshHighlights()
            }

            activeBuffer.filePath = destinationPath
            activeBuffer.fileName = savedName
            activeBuffer.language = savedLanguage
            activeBuffer.lineEnding = currentLineEnding
            activeBuffer.lastModifiedDate = savedDate
            activeBuffer.didInvalidateHistoryOnLastRefresh = false
            if let currentSnapshot = activeBufferSnapshot() {
                activeBuffer.editHistory.markSaved(currentSnapshot)
                activeBuffer.isDirty = activeBuffer.editHistory.isDirty(current: currentSnapshot)
            } else {
                activeBuffer.isDirty = false
            }

            if !previousPath.isEmpty && previousPath != destinationPath {
                fileWatcherIntegration?.unwatchClosedFile(previousPath)
            }
            fileWatcherIntegration?.watchOpenedFile(destinationPath)

            if previousPath != destinationPath {
                Task { [weak self] in
                    await self?.loadInitialTree()
                    await MainActor.run {
                        self?.renderRefreshSource?.invalidate()
                    }
                }
            }

            gitDecorationManager?.scheduleRefreshForActiveBuffer(debounced: false)
            statusMessage = "Saved: \(savedName)"
            refreshGitStatusAfterSave()
            return true
        } catch {
            activeBuffer.filePath = previousPath
            activeBuffer.fileName = previousName
            activeBuffer.language = previousLanguage
            statusMessage = "Error saving: \(error.localizedDescription)"
            return false
        }
    }

    func writeBufferToDisk() {
        guard !filePath.isEmpty else { return }
        _ = writeBufferToDisk(at: filePath)
    }

    func closeCurrentTab() {
        guard bufferManager.count > 0 else { return }
        let index = bufferManager.activeIndex
        let closedPath = bufferManager.buffers[index].filePath
        let result = bufferManager.close(at: index)
        switch result {
        case .promptSave:
            statusMessage = "Buffer has unsaved changes. Save first (^O) or force close."
        case .closed:
            if !closedPath.isEmpty {
                fileWatcherIntegration?.unwatchClosedFile(closedPath)
            }
            // Clamp open files scroll offset after removing a buffer
            if openFilesScrollOffset > 0 {
                openFilesScrollOffset = min(openFilesScrollOffset, max(0, bufferManager.count - 1))
            }
            if bufferManager.isEmpty {
                // Reset to empty editor state
                fileName = ""
                filePath = ""
                currentLanguage = nil
                replaceDocumentText(with: "")
                textCursor = TextCursor()
                highlightedLines = [[StyledSpan(text: "", style: .default)]]
                invalidateHighlightSession()
                prompt = nil
                mode = .tree
                statusMessage = "All buffers closed"
            } else {
                restoreStateFromActiveBuffer()
                refreshHighlights()
                gitDecorationManager?.scheduleRefreshForActiveBuffer(debounced: false)
            }
        }
    }

    private func prewarmVisibleSyntaxArtifacts(limit: Int = 16) {
        let languages = visibleLanguagesForSyntaxPrewarm(limit: limit)
        guard !languages.isEmpty else { return }

        Task(priority: .userInitiated) {
            await LanguageHighlighter.prewarmArtifacts(for: languages)
        }
    }

    private func visibleLanguagesForSyntaxPrewarm(limit: Int) -> [String] {
        var languages: [String] = []
        var seenLanguages = Set<String>()

        for (_, node) in cachedFlatTree where !node.isDirectory {
            guard let language = Self.detectLanguage(for: node.name),
                seenLanguages.insert(language).inserted
            else {
                continue
            }

            languages.append(language)
            if languages.count == limit {
                break
            }
        }

        return languages
    }

    private func refreshGitStatusAfterSave() {
        guard let provider = fileStatusProvider else { return }

        Task { [weak self] in
            await provider.refresh()
            await MainActor.run {
                self?.gitDecorationManager?.scheduleRefreshForActiveBuffer(debounced: false)
                self?.renderRefreshSource?.invalidate()
            }
        }
    }

    private func finishOpeningFile(
        requestID: UInt64,
        path: String,
        name: String,
        content: String,
        language: String?,
        modificationDate: Date?,
        lineEnding: TextDocument.LineEnding
    ) {
        guard isCurrentOpenRequest(requestID) else { return }

        let newIndex: Int
        if config.tabRibbon.persistence == .preview {
            newIndex = bufferManager.openPreview(
                filePath: path,
                fileName: name,
                content: content,
                language: language,
                lineEnding: lineEnding,
                maxUndoSteps: config.editor.maxUndoSteps
            )
        } else {
            newIndex = bufferManager.open(
                filePath: path,
                fileName: name,
                content: content,
                language: language,
                lineEnding: lineEnding,
                maxUndoSteps: config.editor.maxUndoSteps
            )
        }

        let buffer = bufferManager.buffers[newIndex]
        buffer.lastModifiedDate = modificationDate
        buffer.selection = nil
        buffer.highlightedLines = []
        buffer.highlightSession = nil
        buffer.cachedMaxLineWidth = nil
        buffer.lineEnding = lineEnding
        buffer.didInvalidateHistoryOnLastRefresh = false
        buffer.editHistory.reset(
            to: BufferEditSnapshot(
                textBuffer: buffer.textBuffer,
                textCursor: buffer.textCursor,
                lineEnding: buffer.lineEnding
            )
        )

        restoreStateFromActiveBuffer()
        prompt = nil
        highlightedLines = []
        highlightSession = nil
        cachedMaxLineWidth = nil
        currentLineEnding = lineEnding
        noteSelectedPath(path, isDirectory: false)

        gitDecorationManager?.scheduleRefreshForActiveBuffer(debounced: false)
        mode = .editor
        let resolver = KeymapResolver(config: config)
        statusMessage = "Opened \(name) | \(resolver.openedStatusHints())"
        if config.keybindingMode == .vim {
            vimMode = .normal
            statusMessage = "-- NORMAL -- [\(name)] :w=Save, :q=Quit"
        }

        fileWatcherIntegration?.watchOpenedFile(path)
        renderRefreshSource?.invalidate()
        schedulePostLoadProcessing(for: buffer, content: content)
    }

    func schedulePostLoadProcessing(for buffer: DocumentBuffer, content: String) {
        buffer.postOpenProcessingTask?.cancel()

        let version = buffer.documentVersion
        let language = buffer.language
        let theme = syntaxTheme
        let textBuffer = buffer.textBuffer
        let shouldHighlight =
            config.syntax.enabled
            && !(language.map(config.syntax.disabledLanguages.contains) ?? false)
        let showGrammarLoading = shouldHighlight && language != nil
        let tabSize = config.editor.tabSize

        if bufferManager.activeBuffer === buffer {
            isLoadingGrammar = showGrammarLoading
        }

        buffer.postOpenProcessingTask = Task { [weak self, weak buffer] in
            enum PostLoadResult {
                case maxLineWidth(Int)
                case highlightedLines([[StyledSpan]])
            }

            let (maxLineWidth, highlightedLines) = await withTaskGroup(
                of: PostLoadResult.self,
                returning: (Int, [[StyledSpan]]?).self
            ) { group in
                group.addTask(priority: .utility) {
                    .maxLineWidth(
                        TextDocument.computeMaxLineWidth(in: textBuffer, tabSize: tabSize))
                }

                if shouldHighlight {
                    group.addTask(priority: .userInitiated) {
                        if let language {
                            _ = await LanguageHighlighter.ensureArtifacts(for: language)
                        }
                        return .highlightedLines(
                            LanguageHighlighter.highlightDocument(
                                source: content,
                                language: language,
                                theme: theme
                            )
                        )
                    }
                }

                var resolvedMaxLineWidth = 0
                var resolvedHighlightedLines: [[StyledSpan]]?

                for await result in group {
                    switch result {
                    case .maxLineWidth(let width):
                        resolvedMaxLineWidth = width
                    case .highlightedLines(let lines):
                        resolvedHighlightedLines = lines
                    }
                }

                return (resolvedMaxLineWidth, resolvedHighlightedLines)
            }

            guard !Task.isCancelled else { return }
            guard let self, let buffer else { return }
            guard buffer.documentVersion == version else { return }

            buffer.cachedMaxLineWidth = maxLineWidth
            if let highlightedLines {
                buffer.highlightedLines = highlightedLines
                buffer.highlightSession = nil
            }
            buffer.postOpenProcessingTask = nil

            if self.bufferManager.activeBuffer === buffer {
                self.cachedMaxLineWidth = maxLineWidth
                if let highlightedLines {
                    self.highlightedLines = highlightedLines
                    self.markContentAllDirty()
                }
                self.isLoadingGrammar = false
                self.renderRefreshSource?.invalidate()
            }
        }
    }
}

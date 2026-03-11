import Foundation
import KittyFileTree
import KittySyntax
import KittyText

extension EditorState {
    private static let maxFileSize = 50_000_000  // 50MB

    func loadInitialTree() async {
        let expandedPaths = collectExpandedPaths(treeNodes)
        treeNodes = await DirectoryScanner.scanAsync(rootPath, maxDepth: 1)
        if !expandedPaths.isEmpty {
            restoreExpandedPaths(expandedPaths, in: &treeNodes)
        }
        refreshFlatTree()
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
                    FileTreeNavigator.toggleExpand(in: &nodes, at: nodes[i].path)
                }
                if !nodes[i].children.isEmpty {
                    restoreExpandedPaths(paths, in: &nodes[i].children)
                }
            }
        }
    }

    func refreshFlatTree() {
        cachedFlatTree = FileTreeNavigator.flatten(treeNodes)
        prewarmVisibleSyntaxArtifacts()
    }

    func toggleExpand(at index: Int) {
        let flat = cachedFlatTree
        guard index < flat.count else { return }
        let node = flat[index].node
        guard node.isDirectory else { return }
        FileTreeNavigator.toggleExpand(in: &treeNodes, at: node.path)
        refreshFlatTree()
    }

    func openFile(at index: Int) {
        let flat = cachedFlatTree
        guard index < flat.count else { return }
        let node = flat[index].node
        guard !node.isDirectory else { return }

        openFilePath(node.path, name: node.name)
    }

    func openFilePath(_ path: String, name: String) {
        // Path traversal protection
        guard SecurePath.isValid(path, root: rootPath) else {
            statusMessage = "Access denied: path outside project root"
            return
        }

        // If already open, just switch to it
        if let existingIndex = bufferManager.bufferIndex(forPath: path) {
            if existingIndex != bufferManager.activeIndex {
                switchToTab(existingIndex)
            }
            mode = .editor
            statusMessage = "Opened \(name) | ^O: Save, ^X: Tree/Quit"
            if config.keybindingMode == .vim {
                vimMode = .normal
                statusMessage = "-- NORMAL -- [\(name)] :w=Save, :q=Quit"
            }
            return
        }

        let fileManager = FileManager.default
        let attributes = try? fileManager.attributesOfItem(atPath: path)
        if let fileSize = attributes?[.size] as? Int,
           fileSize > Self.maxFileSize {
            statusMessage = "File too large (\(fileSize / 1_000_000)MB, limit \(Self.maxFileSize / 1_000_000)MB)"
            return
        }

        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            statusMessage = "Cannot read: \(name)"
            return
        }

        // Save current buffer state before switching
        saveStateToActiveBuffer()

        let language = Self.detectLanguage(for: name)
        let modDate = attributes?[.modificationDate] as? Date

        let newIndex = bufferManager.open(
            filePath: path,
            fileName: name,
            content: content,
            language: language
        )
        bufferManager.buffers[newIndex].lastModifiedDate = modDate

        // Restore from the new buffer
        restoreStateFromActiveBuffer()
        refreshHighlights()
        mode = .editor
        statusMessage = "Opened \(name) | ^O: Save, ^X: Tree/Quit"
        if config.keybindingMode == .vim {
            vimMode = .normal
            statusMessage = "-- NORMAL -- [\(name)] :w=Save, :q=Quit"
        }

        // Load grammar artifacts off the main thread, then re-highlight with full syntax
        if let language = currentLanguage,
           config.syntaxHighlighting,
           !config.disabledLanguages.contains(language) {
            Task {
                let available = await LanguageHighlighter.ensureArtifacts(for: language)
                if available {
                    self.invalidateHighlightSession()
                    self.refreshHighlights()
                }
            }
        }

        // Watch the new file
        // (FileWatcherIntegration handles this via AppMain)
    }

    /// Detect language name from file extension.
    static func detectLanguage(for filename: String) -> String? {
        LanguageHighlighter.detectLanguage(for: filename)
    }

    func saveFile() {
        guard !filePath.isEmpty else { return }

        guard SecurePath.isValid(filePath, root: rootPath) else {
            statusMessage = "Access denied: cannot save outside project root"
            return
        }

        writeBufferToDisk()
    }

    func writeBufferToDisk() {
        guard !filePath.isEmpty else { return }
        let content = documentText
        do {
            try content.write(toFile: filePath, atomically: true, encoding: .utf8)
            bufferManager.activeBuffer?.isDirty = false
            bufferManager.activeBuffer?.lastModifiedDate = Date()
            statusMessage = "Saved: \(fileName)"
            if let provider = fileStatusProvider {
                Task { await provider.refresh() }
            }
        } catch {
            statusMessage = "Error saving: \(error.localizedDescription)"
        }
    }

    func closeCurrentTab() {
        guard bufferManager.count > 0 else { return }
        let index = bufferManager.activeIndex
        let result = bufferManager.close(at: index)
        switch result {
        case .promptSave:
            statusMessage = "Buffer has unsaved changes. Save first (^O) or force close."
        case .closed:
            if bufferManager.isEmpty {
                // Reset to empty editor state
                fileName = ""
                filePath = ""
                currentLanguage = nil
                replaceDocumentText(with: "")
                textCursor = TextCursor()
                highlightedLines = [[StyledSpan(text: "", style: .default)]]
                invalidateHighlightSession()
                mode = .tree
                statusMessage = "All buffers closed"
            } else {
                restoreStateFromActiveBuffer()
                refreshHighlights()
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
}

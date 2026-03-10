import Foundation
import KittyFileTree
import KittySyntax
import KittyText

extension EditorState {
    private static let maxFileSize = 50_000_000  // 50MB

    func loadInitialTree() async {
        treeNodes = await DirectoryScanner.scanAsync(rootPath, maxDepth: 1)
        refreshFlatTree()
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

        // Path traversal protection
        guard SecurePath.isValid(node.path, root: rootPath) else {
            statusMessage = "Access denied: path outside project root"
            return
        }

        // File size check
        let fileManager = FileManager.default
        if let attrs = try? fileManager.attributesOfItem(atPath: node.path),
           let fileSize = attrs[.size] as? Int,
           fileSize > Self.maxFileSize {
            statusMessage = "File too large (\(fileSize / 1_000_000)MB, limit \(Self.maxFileSize / 1_000_000)MB)"
            return
        }

        guard let data = fileManager.contents(atPath: node.path),
              let content = String(data: data, encoding: .utf8) else {
            statusMessage = "Cannot read: \(node.name)"
            return
        }

        fileName = node.name
        filePath = node.path
        replaceDocumentText(with: content)
        textCursor = TextCursor()
        currentLanguage = Self.detectLanguage(for: node.name)
        refreshHighlights()
        mode = .editor
        statusMessage = "Opened \(node.name) | ^O: Save, ^X: Tree/Quit"
        if config.keybindingMode == .vim {
            vimMode = .normal
            statusMessage = "-- NORMAL -- [\(node.name)] :w=Save, :q=Quit"
        }
    }

    /// Detect language name from file extension.
    static func detectLanguage(for filename: String) -> String? {
        let ext = (filename as NSString).pathExtension
        let extensionMap: [String: String] = [
            "swift": "swift",
            "json": "json",
            "js": "javascript",
            "mjs": "javascript",
            "cjs": "javascript",
            "ts": "typescript",
            "mts": "typescript",
            "cts": "typescript",
            "py": "python",
            "pyi": "python",
            "rs": "rust",
            "go": "go",
            "c": "c",
            "h": "c",
            "cpp": "cpp",
            "hpp": "cpp",
            "cc": "cpp",
            "cxx": "cpp",
            "html": "html",
            "htm": "html",
            "css": "css",
            "sh": "bash",
            "bash": "bash",
            "rb": "ruby",
            "java": "java",
            "kt": "kotlin",
            "kts": "kotlin",
            "lua": "lua",
            "toml": "toml",
            "yml": "yaml",
            "yaml": "yaml",
            "md": "markdown",
            "markdown": "markdown",
        ]
        return extensionMap[ext]
    }

    func saveFile() {
        guard !filePath.isEmpty else { return }

        guard SecurePath.isValid(filePath, root: rootPath) else {
            statusMessage = "Access denied: cannot save outside project root"
            return
        }

        let content = documentText
        do {
            try content.write(toFile: filePath, atomically: true, encoding: .utf8)
            statusMessage = "Saved: \(fileName)"
        } catch {
            statusMessage = "Error saving: \(error.localizedDescription)"
        }
    }

    private func prewarmVisibleSyntaxArtifacts(limit: Int = 8) {
        let languages = visibleLanguagesForSyntaxPrewarm(limit: limit)
        guard !languages.isEmpty else { return }

        Task(priority: .utility) {
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

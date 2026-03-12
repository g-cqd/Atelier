import Foundation
import KittyCodecs
import KittyText

struct EditorPrompt: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case savePath
        case createFile(inDirectory: String)
        case createDirectory(inDirectory: String)
        case rename(path: String)
        case duplicate(path: String)
        case move(path: String)
        case confirmDelete(path: String)
    }

    var kind: Kind
    var promptText: String
    var input: String
    var message: String?

    var isEditable: Bool {
        switch kind {
        case .confirmDelete:
            return false
        case .savePath, .createFile, .createDirectory, .rename, .duplicate, .move:
            return true
        }
    }

    var submitLabel: String {
        switch kind {
        case .savePath:
            return "Save"
        case .createFile, .createDirectory:
            return "Create"
        case .rename:
            return "Rename"
        case .duplicate:
            return "Duplicate"
        case .move:
            return "Move"
        case .confirmDelete:
            return "Delete"
        }
    }

    var displayText: String {
        if let message {
            return "\(message)  \(promptText)\(input)"
        }
        return promptText + input
    }
}

extension EditorState {
    var displayedStatusMessage: String {
        prompt?.displayText ?? statusMessage
    }

    var promptCursorOffset: Int? {
        guard let prompt else { return nil }
        return prompt.isEditable ? prompt.displayText.count : nil
    }

    func beginNewFile() {
        prompt = nil
        contextMenu = nil
        saveStateToActiveBuffer()

        let untitledIndex = bufferManager.open(
            filePath: "",
            fileName: "Untitled",
            content: "",
            language: nil
        )
        bufferManager.buffers[untitledIndex].isPreview = false

        restoreStateFromActiveBuffer()
        refreshHighlights()
        textCursor = TextCursor()
        mode = .editor
        statusMessage = "New file | ^O: Save, ^X: Tree/Quit"
    }

    func beginSavePrompt(suggestedPath: String? = nil) {
        if bufferManager.activeBuffer == nil {
            beginNewFile()
        }

        contextMenu = nil
        prompt = EditorPrompt(
            kind: .savePath,
            promptText: "Save as: ",
            input: suggestedPath ?? defaultSavePathSuggestion()
        )
    }

    func beginCreateFilePrompt(in directory: String) {
        contextMenu = nil
        prompt = EditorPrompt(
            kind: .createFile(inDirectory: directory),
            promptText: "New file: ",
            input: promptDirectorySuggestion(for: directory)
        )
    }

    func beginCreateDirectoryPrompt(in directory: String) {
        contextMenu = nil
        prompt = EditorPrompt(
            kind: .createDirectory(inDirectory: directory),
            promptText: "New folder: ",
            input: promptDirectorySuggestion(for: directory)
        )
    }

    func beginRenamePrompt(for path: String) {
        contextMenu = nil
        prompt = EditorPrompt(
            kind: .rename(path: path),
            promptText: "Rename to: ",
            input: relativePathForPrompt(path)
        )
    }

    func beginDuplicatePrompt(for path: String) {
        contextMenu = nil
        prompt = EditorPrompt(
            kind: .duplicate(path: path),
            promptText: "Duplicate to: ",
            input: duplicateSuggestion(for: path)
        )
    }

    func beginMovePrompt(for path: String) {
        contextMenu = nil
        prompt = EditorPrompt(
            kind: .move(path: path),
            promptText: "Move to: ",
            input: relativePathForPrompt(path)
        )
    }

    func beginDeletePrompt(for path: String) {
        contextMenu = nil
        prompt = EditorPrompt(
            kind: .confirmDelete(path: path),
            promptText: "Delete \(relativePathForPrompt(path))? ",
            input: ""
        )
    }

    func handlePromptKey(_ key: KeyEvent) -> Bool {
        guard var prompt else { return false }

        switch key.keyCode {
        case Key.enter.rawValue, Key.enterAlt.rawValue:
            if commit(prompt: prompt) {
                self.prompt = nil
            }
            return true
        case AsciiKey.escape:
            self.prompt = nil
            statusMessage = "Canceled"
            return true
        case Key.backspace.rawValue, Key.backspaceAlt.rawValue:
            guard prompt.isEditable else { return true }
            if !prompt.input.isEmpty {
                prompt.input.removeLast()
            }
            prompt.message = nil
            self.prompt = prompt
            return true
        default:
            guard prompt.isEditable else { return true }
            let insertedText = promptText(for: key)
            guard !insertedText.isEmpty else { return true }
            prompt.input += insertedText
            prompt.message = nil
            self.prompt = prompt
            return true
        }
    }

    private func commit(prompt: EditorPrompt) -> Bool {
        switch prompt.kind {
        case .savePath:
            let trimmedPath = prompt.input.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedPath.isEmpty else {
                self.prompt = EditorPrompt(
                    kind: prompt.kind,
                    promptText: prompt.promptText,
                    input: prompt.input,
                    message: "Path required"
                )
                return false
            }
            let saveSucceeded = writeBufferToDisk(at: resolvePromptPath(trimmedPath))
            if !saveSucceeded {
                self.prompt = EditorPrompt(
                    kind: prompt.kind,
                    promptText: prompt.promptText,
                    input: prompt.input,
                    message: statusMessage
                )
            }
            return saveSucceeded
        case .createFile(let directory):
            let trimmedPath = prompt.input.trimmingCharacters(in: .whitespacesAndNewlines)
            return commitTreePathPrompt(prompt, trimmedPath: trimmedPath) {
                await self.createTreeFile(at: self.resolvePromptPath(trimmedPath), suggestedDirectory: directory)
            }
        case .createDirectory(let directory):
            let trimmedPath = prompt.input.trimmingCharacters(in: .whitespacesAndNewlines)
            return commitTreePathPrompt(prompt, trimmedPath: trimmedPath) {
                await self.createTreeDirectory(at: self.resolvePromptPath(trimmedPath), suggestedDirectory: directory)
            }
        case .rename(let path):
            let trimmedPath = prompt.input.trimmingCharacters(in: .whitespacesAndNewlines)
            return commitTreePathPrompt(prompt, trimmedPath: trimmedPath) {
                await self.renameTreeItem(from: path, to: self.resolvePromptPath(trimmedPath))
            }
        case .duplicate(let path):
            let trimmedPath = prompt.input.trimmingCharacters(in: .whitespacesAndNewlines)
            return commitTreePathPrompt(prompt, trimmedPath: trimmedPath) {
                await self.duplicateTreeItem(at: path, to: self.resolvePromptPath(trimmedPath))
            }
        case .move(let path):
            let trimmedPath = prompt.input.trimmingCharacters(in: .whitespacesAndNewlines)
            return commitTreePathPrompt(prompt, trimmedPath: trimmedPath) {
                await self.moveTreeItem(from: path, to: self.resolvePromptPath(trimmedPath))
            }
        case .confirmDelete(let path):
            Task { @MainActor in
                if !(await deleteTreeItem(at: path)) {
                    self.prompt = EditorPrompt(
                        kind: prompt.kind,
                        promptText: prompt.promptText,
                        input: prompt.input,
                        message: self.statusMessage
                    )
                } else {
                    self.prompt = nil
                }
            }
            return false
        }
    }

    private func commitTreePathPrompt(
        _ prompt: EditorPrompt,
        trimmedPath: String,
        operation: @escaping @MainActor () async -> Bool
    ) -> Bool {
        guard !trimmedPath.isEmpty else {
            self.prompt = EditorPrompt(
                kind: prompt.kind,
                promptText: prompt.promptText,
                input: prompt.input,
                message: "Path required"
            )
            return false
        }

        Task { @MainActor in
            if !(await operation()) {
                self.prompt = EditorPrompt(
                    kind: prompt.kind,
                    promptText: prompt.promptText,
                    input: prompt.input,
                    message: self.statusMessage
                )
            } else {
                self.prompt = nil
            }
        }
        return false
    }

    private func defaultSavePathSuggestion() -> String {
        if !filePath.isEmpty {
            return relativePathForPrompt(filePath)
        }

        guard let lastSelectedDirectoryPath else { return "" }
        let relativePath = relativePathForPrompt(lastSelectedDirectoryPath)
        if relativePath.isEmpty || relativePath == "." {
            return ""
        }
        return relativePath.hasSuffix("/") ? relativePath : relativePath + "/"
    }

    func relativePathForPrompt(_ path: String) -> String {
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        if path.hasPrefix(rootPrefix) {
            return String(path.dropFirst(rootPrefix.count))
        }
        return path
    }

    private func resolvePromptPath(_ input: String) -> String {
        let expandedPath = (input as NSString).expandingTildeInPath
        if expandedPath.hasPrefix("/") {
            return URL(fileURLWithPath: expandedPath).standardizedFileURL.path
        }
        return URL(fileURLWithPath: rootPath)
            .appendingPathComponent(expandedPath)
            .standardizedFileURL.path
    }

    private func promptText(for key: KeyEvent) -> String {
        if !key.associatedText.isEmpty {
            return key.associatedText
        }

        guard key.modifiers.isEmpty, key.keyCode < 256, let scalar = UnicodeScalar(key.keyCode) else {
            return ""
        }

        let character = Character(scalar)
        return character.isPrintable ? String(character) : ""
    }

    private func duplicateSuggestion(for path: String) -> String {
        let url = URL(fileURLWithPath: path)
        let directory = url.deletingLastPathComponent()
        let fileName = url.deletingPathExtension().lastPathComponent
        let fileExtension = url.pathExtension
        let duplicatedName = if fileExtension.isEmpty {
            fileName + " copy"
        } else {
            fileName + " copy." + fileExtension
        }
        return relativePathForPrompt(directory.appendingPathComponent(duplicatedName).path)
    }

    private func promptDirectorySuggestion(for directory: String) -> String {
        let relativePath = relativePathForPrompt(directory)
        if relativePath.isEmpty || relativePath == "." {
            return ""
        }
        return relativePath.hasSuffix("/") ? relativePath : relativePath + "/"
    }
}

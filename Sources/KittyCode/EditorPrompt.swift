import Foundation
import KittyCodecs
import KittyText

struct EditorPrompt: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case savePath
    }

    var kind: Kind
    var promptText: String
    var input: String
    var message: String?

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
        prompt.map { $0.displayText.count }
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
            if !prompt.input.isEmpty {
                prompt.input.removeLast()
            }
            prompt.message = nil
            self.prompt = prompt
            return true
        default:
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
        }
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
}

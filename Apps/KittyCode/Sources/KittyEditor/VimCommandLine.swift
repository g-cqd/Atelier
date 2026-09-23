public import KittyCodecs
import KittyInput

public struct VimCommandLine: Sendable, Equatable {
    public var buffer: String = ""

    public var displayText: String { ":" + buffer }
}

extension EditorState {
    @MainActor
    public func handleVimCommandLineKey(_ key: KeyEvent) -> Bool {
        switch key.keyCode {
            case Key.enter.rawValue, Key.enterAlt.rawValue:
                let command = vimCommandLine?.buffer ?? ""
                vimCommandLine = nil
                return executeVimExCommand(command)

            case AsciiKey.escape:
                vimCommandLine = nil
                statusMessage = "-- NORMAL -- [\(fileName)] :w=Save, :q=Quit"
                return true

            case Key.backspace.rawValue, Key.backspaceAlt.rawValue:
                if vimCommandLine?.buffer.isEmpty == true {
                    vimCommandLine = nil
                    statusMessage = "-- NORMAL -- [\(fileName)] :w=Save, :q=Quit"
                } else {
                    vimCommandLine?.buffer.removeLast()
                    statusMessage = vimCommandLine?.displayText ?? ":"
                }
                return true

            default:
                if let text = textInsertion(for: key, allowTab: false) {
                    vimCommandLine?.buffer.append(text)
                    statusMessage = vimCommandLine?.displayText ?? ":"
                }
                return true
        }
    }

    @MainActor
    public func executeVimExCommand(_ command: String) -> Bool {
        switch command {
            case "w":
                saveFile()
                return true

            case "w!":
                forceSaveFile()
                return true

            case "e!":
                reloadActiveBufferFromDisk()
                return true

            case "q":
                if mode == .editor {
                    mode = .tree
                    let resolver = KeymapResolver(config: config)
                    statusMessage = "Ready | \(resolver.statusHints())"
                    return true
                }
                return false

            case "wq", "x":
                return saveAndLeave(overwritingDiskChanges: false)

            case "wq!", "x!":
                return saveAndLeave(overwritingDiskChanges: true)

            case "q!":
                return false

            default:
                statusMessage = "Unknown command: :\(command)"
                return true
        }
    }

    /// Saves, then leaves the editor for the tree, or quits when already in the tree. A save that is refused or fails
    /// stays put, so its message shows and nothing is lost.
    /// - Returns: False to quit the app.
    @MainActor
    private func saveAndLeave(overwritingDiskChanges: Bool) -> Bool {
        guard saveFile(overwritingDiskChanges: overwritingDiskChanges) else { return true }
        guard mode == .editor else { return false }
        mode = .tree
        let resolver = KeymapResolver(config: config)
        statusMessage = "Ready | \(resolver.statusHints())"
        return true
    }
}

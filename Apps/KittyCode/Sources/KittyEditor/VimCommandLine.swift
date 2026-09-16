public import KittyCodecs
import KittyInput

public struct VimCommandLine: Sendable, Equatable {
    public var buffer: String = ""

    public var displayText: String { ":" + buffer }
}

public extension EditorState {
    @MainActor
    func handleVimCommandLineKey(_ key: KeyEvent) -> Bool {
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
    func executeVimExCommand(_ command: String) -> Bool {
        switch command {
        case "w":
            saveFile()
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
            saveFile()
            if mode == .editor {
                mode = .tree
                let resolver = KeymapResolver(config: config)
                statusMessage = "Ready | \(resolver.statusHints())"
                return true
            }
            return false

        case "q!":
            return false

        default:
            statusMessage = "Unknown command: :\(command)"
            return true
        }
    }
}

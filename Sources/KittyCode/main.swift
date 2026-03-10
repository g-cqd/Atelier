import Foundation
import KittyApp
import KittyWidgets
import KittyCodecs
import KittyInput
import KittyRenderer
import KittyTerminal
import KittySyntax

// MARK: - Configuration

struct KittyConfig: Codable, Sendable {
    enum KeybindingMode: String, Codable, Sendable {
        case nano
        case vim
    }
    
    struct ColorRGB: Codable, Sendable {
        var r: UInt8
        var g: UInt8
        var b: UInt8
        
        var color: Color { .rgb(r: r, g: g, b: b) }
    }
    
    struct Theme: Codable, Sendable {
        var backgroundColor: ColorRGB = ColorRGB(r: 0x1e, g: 0x1e, b: 0x1e)
        var treePanelBackground: ColorRGB = ColorRGB(r: 0x18, g: 0x18, b: 0x18)
        var treePanelForeground: ColorRGB = ColorRGB(r: 0xcc, g: 0xcc, b: 0xcc)
        var treeSelectedBackground: ColorRGB = ColorRGB(r: 0x26, g: 0x4f, b: 0x78)
        var treeSelectedForeground: ColorRGB = ColorRGB(r: 0xff, g: 0xff, b: 0xff)
        var editorForeground: ColorRGB = ColorRGB(r: 0xd4, g: 0xd4, b: 0xd4)
        var editorCursorLineBackground: ColorRGB = ColorRGB(r: 0x28, g: 0x28, b: 0x28)
        var statusBarBackground: ColorRGB = ColorRGB(r: 0x00, g: 0x7a, b: 0xcc)
        var statusBarForeground: ColorRGB = ColorRGB(r: 0xff, g: 0xff, b: 0xff)
        var titleBarBackground: ColorRGB = ColorRGB(r: 0x32, g: 0x32, b: 0x32)
        var titleBarForeground: ColorRGB = ColorRGB(r: 0xcc, g: 0xcc, b: 0xcc)
    }
    
    var keybindingMode: KeybindingMode = .nano
    var wrapLines: Bool = false
    var treeWidth: Int = 30
    var theme: Theme = Theme()
    
    static func load() -> KittyConfig {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let configURL = home.appendingPathComponent(".kittycode.json")
        if let data = try? Data(contentsOf: configURL),
           let config = try? JSONDecoder().decode(KittyConfig.self, from: data) {
            return config
        }
        return KittyConfig()
    }
}

// MARK: - File Tree Model

struct FileEntry: Sendable {
    let name: String
    let path: String
    let isDirectory: Bool
    var children: [FileEntry]
    var isExpanded: Bool

    var icon: String {
        if isDirectory {
            return isExpanded ? "[-]" : "[+]"
        }
        return "   "
    }
}

// MARK: - Editor State

@MainActor
final class EditorState {
    var config: KittyConfig
    var colorScheme: ColorScheme
    var rootPath: String
    
    struct ColorScheme {
        var bg: Style
        var treeBg: Style
        var treeSelected: Style
        var treeDir: Style
        var lineNumber: Style
        var editorText: Style
        var editorCursorLine: Style
        var statusBar: Style
        var titleBar: Style
        var separator: Style
    }
    var fileTree: [FileEntry] = []
    var flatTree: [(depth: Int, entry: FileEntry)] = []
    var selectedTreeIndex: Int = 0
    var treeScrollOffset: Int = 0

    var fileContent: [String] = []
    var fileName: String = ""
    var filePath: String = ""
    var scrollOffset: Int = 0
    var hScrollOffset: Int = 0
    var cursorRow: Int = 0
    var cursorCol: Int = 0

    var treePanelWidth: Int = 30
    var statusMessage: String = ""
    var mode: Mode = .tree
    var vimMode: VimSubMode = .normal

    var lastClickTime: Date = .distantPast
    var lastClickIndex: Int = -1
    var isScrolling: Bool = false

    enum Mode { case tree, editor }
    enum VimSubMode { case normal, insert }

    init(rootPath: String, config: KittyConfig) {
        self.rootPath = rootPath
        self.config = config
        self.treePanelWidth = config.treeWidth
        self.colorScheme = Self.makeColorScheme(config: config)
        self.fileTree = Self.scanDirectory(rootPath, maxDepth: 1)
        self.flatTree = Self.flatten(fileTree)
        self.statusMessage = "Opened: \(rootPath) | ^O: Save, ^X: Quit"
    }

    static func makeColorScheme(config: KittyConfig) -> ColorScheme {
        let t = config.theme
        return ColorScheme(
            bg: Style(bg: t.backgroundColor.color),
            treeBg: Style(fg: t.treePanelForeground.color, bg: t.treePanelBackground.color),
            treeSelected: Style(fg: t.treeSelectedForeground.color, bg: t.treeSelectedBackground.color),
            treeDir: Style(fg: .rgb(r: 0x81, g: 0xc7, b: 0x84), bg: t.treePanelBackground.color, bold: true),
            lineNumber: Style(fg: .rgb(r: 0x64, g: 0x64, b: 0x64), bg: t.backgroundColor.color),
            editorText: Style(fg: t.editorForeground.color, bg: t.backgroundColor.color),
            editorCursorLine: Style(fg: t.editorForeground.color, bg: t.editorCursorLineBackground.color),
            statusBar: Style(fg: t.statusBarForeground.color, bg: t.statusBarBackground.color),
            titleBar: Style(fg: t.titleBarForeground.color, bg: t.titleBarBackground.color),
            separator: Style(fg: .rgb(r: 0x3c, g: 0x3c, b: 0x3c), bg: t.backgroundColor.color)
        )
    }

    static func scanDirectory(_ path: String, maxDepth: Int) -> [FileEntry] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: path) else { return [] }
        var entries: [FileEntry] = []
        for item in items.sorted() where !item.hasPrefix(".") {
            let fullPath = (path as NSString).appendingPathComponent(item)
            var isDir: ObjCBool = false
            fm.fileExists(atPath: fullPath, isDirectory: &isDir)
            var children: [FileEntry] = []
            if isDir.boolValue && maxDepth > 0 {
                children = scanDirectory(fullPath, maxDepth: maxDepth - 1)
            }
            entries.append(FileEntry(
                name: item, path: fullPath,
                isDirectory: isDir.boolValue, children: children,
                isExpanded: false
            ))
        }
        // Sort: directories first, then files
        return entries.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    static func flatten(_ entries: [FileEntry], depth: Int = 0) -> [(depth: Int, entry: FileEntry)] {
        var result: [(depth: Int, entry: FileEntry)] = []
        for entry in entries {
            result.append((depth: depth, entry: entry))
            if entry.isDirectory && entry.isExpanded {
                result.append(contentsOf: flatten(entry.children, depth: depth + 1))
            }
        }
        return result
    }

    func refreshFlatTree() {
        flatTree = Self.flatten(fileTree)
    }

    func toggleExpand(at index: Int) {
        guard index < flatTree.count else { return }
        let entry = flatTree[index].entry
        guard entry.isDirectory else { return }
        toggleInTree(&fileTree, path: entry.path)
        refreshFlatTree()
    }

    private func toggleInTree(_ entries: inout [FileEntry], path: String) {
        for i in entries.indices {
            if entries[i].path == path {
                entries[i].isExpanded.toggle()
                if entries[i].isExpanded && entries[i].children.isEmpty {
                    entries[i].children = Self.scanDirectory(entries[i].path, maxDepth: 1)
                }
                return
            }
            if entries[i].isDirectory {
                toggleInTree(&entries[i].children, path: path)
            }
        }
    }

    func openFile(at index: Int) {
        guard index < flatTree.count else { return }
        let entry = flatTree[index].entry
        guard !entry.isDirectory else { return }
        guard let data = FileManager.default.contents(atPath: entry.path),
              let content = String(data: data, encoding: .utf8) else {
            statusMessage = "Cannot read: \(entry.name)"
            return
        }
        fileName = entry.name
        filePath = entry.path
        fileContent = content.components(separatedBy: "\n")
        scrollOffset = 0
        hScrollOffset = 0
        cursorRow = 0
        cursorCol = 0
        mode = .editor
        statusMessage = "Opened \(entry.name) | ^O: Save, ^X: Tree/Quit"
        if config.keybindingMode == .vim {
            vimMode = .normal
            statusMessage = "-- NORMAL -- [\(entry.name)] :w=Save, :q=Quit"
        }
    }

    func saveFile() {
        guard !filePath.isEmpty else { return }
        let content = fileContent.joined(separator: "\n")
        do {
            try content.write(toFile: filePath, atomically: true, encoding: .utf8)
            statusMessage = "Saved: \(fileName)"
        } catch {
            statusMessage = "Error saving: \(error.localizedDescription)"
        }
    }
}

// MARK: - Render

func highlightSwift(_ line: String, colorScheme: EditorState.ColorScheme) -> [StyledSpan] {
    let keywords = ["import", "struct", "class", "enum", "func", "var", "let", "guard", "if", "else", "switch", "case", "return", "default", "final", "extension", "public", "private", "static", "mutating", "override", "init", "deinit", "typealias", "where", "while", "for", "in", "do", "catch", "try", "throw", "throws", "as", "is", "self", "nil", "true", "false"]
    let types = ["String", "Int", "Bool", "Double", "Float", "Any", "Array", "Dictionary", "Optional", "UInt32", "UInt8", "Date", "Data"]

    var spans: [StyledSpan] = []
    var current = ""
    let chars = Array(line)
    var i = 0
    
    while i < chars.count {
        let char = chars[i]
        if char.isWhitespace || "(){}[],.+-*/=<>!&|".contains(char) {
            if !current.isEmpty {
                var style = colorScheme.editorText
                if keywords.contains(current) {
                    style = Style(fg: .rgb(r: 197, g: 134, b: 192))
                } else if types.contains(current) {
                    style = Style(fg: .rgb(r: 78, g: 201, b: 176))
                }
                spans.append(StyledSpan(text: current, style: style))
                current = ""
            }
            spans.append(StyledSpan(text: String(char), style: colorScheme.editorText))
            i += 1
        } else if char == "/" && i + 1 < chars.count && chars[i+1] == "/" {
            if !current.isEmpty {
                spans.append(StyledSpan(text: current, style: colorScheme.editorText))
                current = ""
            }
            spans.append(StyledSpan(text: String(chars[i...]), style: Style(fg: .rgb(r: 106, g: 153, b: 85))))
            break
        } else if char == "\"" {
            if !current.isEmpty {
                spans.append(StyledSpan(text: current, style: colorScheme.editorText))
                current = ""
            }
            var str = "\""
            i += 1
            while i < chars.count && chars[i] != "\"" {
                str.append(chars[i])
                i += 1
            }
            if i < chars.count {
                str.append("\"")
                i += 1
            }
            spans.append(StyledSpan(text: str, style: Style(fg: .rgb(r: 206, g: 145, b: 120))))
        } else {
            current.append(char)
            i += 1
        }
    }
    if !current.isEmpty {
        var style = colorScheme.editorText
        if keywords.contains(current) {
            style = Style(fg: .rgb(r: 197, g: 134, b: 192))
        } else if types.contains(current) {
            style = Style(fg: .rgb(r: 78, g: 201, b: 176))
        }
        spans.append(StyledSpan(text: current, style: style))
    }
    return spans
}

@MainActor
func renderStyledSpans(pipeline: RenderPipeline, spans: [StyledSpan], row: Int, col: Int, availWidth: Int, hScrollOffset: Int, isCurrentLine: Bool, colorScheme: EditorState.ColorScheme) {
    var currentColInRow = col
    var currentX = 0 // x position in the virtual line

    for span in spans {
        let spanChars = Array(span.text)
        for char in spanChars {
            if currentX >= hScrollOffset && currentX < hScrollOffset + availWidth {
                var style = span.style
                if isCurrentLine {
                    style.bg = colorScheme.editorCursorLine.bg
                }
                pipeline.buffer[row, currentColInRow] = Cell(character: char, style: style)
                currentColInRow += 1
            }
            currentX += 1
        }
    }
    
    // Fill remaining space with padding
    while currentColInRow < col + availWidth {
        let style = isCurrentLine ? colorScheme.editorCursorLine : colorScheme.editorText
        pipeline.buffer[row, currentColInRow] = Cell(character: " ", style: style)
        currentColInRow += 1
    }
}

@MainActor
func render(pipeline: RenderPipeline, state: EditorState) {
    let cols = pipeline.columns
    let rows = pipeline.rows
    let colorScheme = state.colorScheme
    guard cols > 0 && rows > 2 else { return }

    let treeWidth = min(state.treePanelWidth, cols / 2)
    let editorStart = treeWidth + 1
    let editorWidth = cols - editorStart
    let contentRows = rows - 2 // title bar + status bar

    // Title bar
    let title = " KittyCode — \(state.rootPath) "
    let titlePadCount = max(0, cols - title.count)
    let titlePad = String(repeating: " ", count: titlePadCount)
    pipeline.buffer.write(String((title + titlePad).prefix(cols)), row: 0, col: 0, style: colorScheme.titleBar)

    // File tree panel
    for r in 0..<contentRows {
        let treeIdx = state.treeScrollOffset + r
        if treeIdx >= 0 && treeIdx < state.flatTree.count {
            let (depth, entry) = state.flatTree[treeIdx]
            let indent = String(repeating: " ", count: depth * 2)
            let label = indent + entry.icon + " " + entry.name
            let paddedCount = max(0, treeWidth - label.count)
            let padded = label + String(repeating: " ", count: paddedCount)
            let style: Style
            if treeIdx == state.selectedTreeIndex {
                style = colorScheme.treeSelected
            } else if entry.isDirectory {
                style = colorScheme.treeDir
            } else {
                style = colorScheme.treeBg
            }
            pipeline.buffer.write(String(padded.prefix(treeWidth)), row: r + 1, col: 0, style: style)
        } else {
            pipeline.buffer.fill(row: r + 1, col: 0, width: treeWidth, height: 1, cell: Cell(character: " ", style: colorScheme.treeBg))
        }

        // Separator
        pipeline.buffer.write("│", row: r + 1, col: treeWidth, style: colorScheme.separator)
    }

    // Editor panel
    let lineNumWidth = max(3, String(state.fileContent.count).count + 1)
    var terminalCursorPos: (row: Int, col: Int)? = nil

    if state.fileContent.isEmpty {
        // Empty state
        let msg = "Open a file from the tree (Enter)"
        let msgRow = contentRows / 2
        for r in 0..<contentRows {
            if r == msgRow {
                let pad = max(0, (editorWidth - msg.count) / 2)
                let line = String(repeating: " ", count: pad) + msg + String(repeating: " ", count: max(0, editorWidth - pad - msg.count))
                pipeline.buffer.write(String(line.prefix(editorWidth)), row: r + 1, col: editorStart, style: Style(fg: .rgb(r: 100, g: 100, b: 100), bg: colorScheme.bg.bg))
            } else {
                pipeline.buffer.fill(row: r + 1, col: editorStart, width: editorWidth, height: 1, cell: Cell(character: " ", style: colorScheme.editorText))
            }
        }
    } else {
        for r in 0..<contentRows {
            let lineIdx = state.scrollOffset + r
            let isCurrentLine = lineIdx == state.cursorRow

            if lineIdx >= 0 && lineIdx < state.fileContent.count {
                // Line number
                let numStr = String(lineIdx + 1)
                let numPad = String(repeating: " ", count: max(0, lineNumWidth - numStr.count - 1))
                pipeline.buffer.write(numPad + numStr + " ", row: r + 1, col: editorStart, style: colorScheme.lineNumber)

                // Line content
                let line = state.fileContent[lineIdx]
                let availWidth = editorWidth - lineNumWidth

                // Basic highlighting
                let spans = highlightSwift(line, colorScheme: colorScheme)
                
                if state.config.wrapLines {
                    // Truncate for now as a simple wrap
                    renderStyledSpans(pipeline: pipeline, spans: spans, row: r + 1, col: editorStart + lineNumWidth, availWidth: availWidth, hScrollOffset: 0, isCurrentLine: isCurrentLine, colorScheme: colorScheme)
                    
                    if isCurrentLine && state.mode == .editor {
                        terminalCursorPos = (row: r + 1, col: editorStart + lineNumWidth + state.cursorCol)
                    }
                } else {
                    renderStyledSpans(pipeline: pipeline, spans: spans, row: r + 1, col: editorStart + lineNumWidth, availWidth: availWidth, hScrollOffset: state.hScrollOffset, isCurrentLine: isCurrentLine, colorScheme: colorScheme)

                    if isCurrentLine && state.mode == .editor {
                        let relativeCol = state.cursorCol - state.hScrollOffset
                        if relativeCol >= 0 && relativeCol < availWidth {
                            terminalCursorPos = (row: r + 1, col: editorStart + lineNumWidth + relativeCol)
                        }
                    }
                }
            } else {
                // Past end of file
                pipeline.buffer.write("~", row: r + 1, col: editorStart, style: colorScheme.lineNumber)
                pipeline.buffer.fill(row: r + 1, col: editorStart + 1, width: editorWidth - 1, height: 1, cell: Cell(character: " ", style: colorScheme.editorText))
            }
        }
    }

    // Status bar
    let modeStr = state.mode == .tree ? "TREE" : "EDIT"
    let posStr = state.fileContent.isEmpty ? "" : "Ln \(state.cursorRow + 1)/\(state.fileContent.count)"
    let statusLeft = " [\(modeStr)] \(state.statusMessage)"
    let statusRight = "\(posStr)  \(cols)x\(rows) "
    let statusPadCount = max(0, cols - statusLeft.count - statusRight.count)
    let statusLine = statusLeft + String(repeating: " ", count: statusPadCount) + statusRight
    pipeline.buffer.write(String(statusLine.prefix(cols)), row: rows - 1, col: 0, style: colorScheme.statusBar)

    // Handle cursor positioning
    if let pos = terminalCursorPos {
        pipeline.cursorRow = pos.row
        pipeline.cursorCol = pos.col
    } else {
        pipeline.cursorRow = nil
        pipeline.cursorCol = nil
    }
}

// MARK: - Event Handling

@MainActor
func handleEvent(event: InputEvent, state: EditorState, pipeline: RenderPipeline) -> Bool {
    let contentRows = pipeline.rows - 2

    switch event {
    case .key(let k):
        // Only handle key press events, ignore repeat/release for now
        guard k.eventType == .press else { return true }

        // Any key press stops scrolling
        state.isScrolling = false

        // Nano-style Global shortcuts
        if k.modifiers == .ctrl {
            if k.keyCode == UInt32(Character("o").asciiValue!) {
                state.saveFile()
                return true
            }
            if k.keyCode == UInt32(Character("x").asciiValue!) {
                if state.mode == .editor {
                    state.mode = .tree
                    state.statusMessage = "Ready | ^O: Save, ^X: Quit"
                    return true
                } else {
                    return false // quit
                }
            }
        }

        // Global: ESC
        if k.keyCode == 27 { // ESC
            if state.mode == .editor {
                if state.config.keybindingMode == .vim {
                    state.vimMode = .normal
                    state.statusMessage = "-- NORMAL -- [\(state.fileName)] :w=Save, :q=Quit"
                } else {
                    state.mode = .tree
                    state.statusMessage = "Ready | ^O: Save, ^X: Quit"
                }
                return true
            } else {
                return false // quit from tree
            }
        }
        if k.keyCode == 3 { return false } // Ctrl+C

        switch state.mode {
        case .tree:
            return handleTreeKey(k, state: state, contentRows: contentRows)
        case .editor:
            return handleEditorKey(k, state: state, contentRows: contentRows, pipeline: pipeline)
        }

    case .mouse(let m):
        handleMouse(m, state: state, pipeline: pipeline)
        return true

    default:
        return true
    }
}

// Decoded functional key codes from SequenceRouter
enum Key: UInt32 {
    case up = 57352
    case down = 57353
    case right = 57354
    case left = 57355
    case enter = 13
    case enterAlt = 10
    case backspace = 127
    case backspaceAlt = 8
}

@MainActor
func handleTreeKey(_ k: KeyEvent, state: EditorState, contentRows: Int) -> Bool {
    switch k.keyCode {
    case Key.down.rawValue:
        state.selectedTreeIndex = min(state.selectedTreeIndex + 1, max(0, state.flatTree.count - 1))
        ensureTreeVisible(state, contentRows: contentRows)
    case Key.up.rawValue:
        state.selectedTreeIndex = max(state.selectedTreeIndex - 1, 0)
        ensureTreeVisible(state, contentRows: contentRows)
    case Key.enter.rawValue, Key.enterAlt.rawValue: // Enter
        guard state.selectedTreeIndex >= 0 && state.selectedTreeIndex < state.flatTree.count else { return true }
        let entry = state.flatTree[state.selectedTreeIndex].entry
        if entry.isDirectory {
            state.toggleExpand(at: state.selectedTreeIndex)
        } else {
            state.openFile(at: state.selectedTreeIndex)
            state.cursorCol = 0
        }
    case Key.right.rawValue: // right arrow — expand or enter
        guard state.selectedTreeIndex >= 0 && state.selectedTreeIndex < state.flatTree.count else { return true }
        let entry = state.flatTree[state.selectedTreeIndex].entry
        if entry.isDirectory && !entry.isExpanded {
            state.toggleExpand(at: state.selectedTreeIndex)
        } else if !entry.isDirectory {
            state.openFile(at: state.selectedTreeIndex)
            state.cursorCol = 0
        }
    case Key.left.rawValue: // left arrow — collapse
        guard state.selectedTreeIndex >= 0 && state.selectedTreeIndex < state.flatTree.count else { return true }
        let entry = state.flatTree[state.selectedTreeIndex].entry
        if entry.isDirectory && entry.isExpanded {
            state.toggleExpand(at: state.selectedTreeIndex)
        }
    default:
        break
    }
    return true
}

@MainActor
func handleEditorKey(_ k: KeyEvent, state: EditorState, contentRows: Int, pipeline: RenderPipeline) -> Bool {
    let treeWidth = min(state.treePanelWidth, pipeline.columns / 2)
    let editorWidth = pipeline.columns - treeWidth - 1
    let lineNumWidth = max(3, String(state.fileContent.count).count + 1)
    let availWidth = editorWidth - lineNumWidth

    if state.config.keybindingMode == .vim && state.vimMode == .normal {
        switch k.keyCode {
        case UInt32(Character("i").asciiValue!):
            state.vimMode = .insert
            state.statusMessage = "-- INSERT -- [\(state.fileName)]"
        case UInt32(Character("h").asciiValue!):
            state.cursorCol = max(0, state.cursorCol - 1)
        case UInt32(Character("j").asciiValue!):
            state.cursorRow = min(state.cursorRow + 1, max(0, state.fileContent.count - 1))
        case UInt32(Character("k").asciiValue!):
            state.cursorRow = max(0, state.cursorRow - 1)
        case UInt32(Character("l").asciiValue!):
            let rowLen = state.fileContent.isEmpty ? 0 : state.fileContent[state.cursorRow].count
            state.cursorCol = min(state.cursorCol + 1, rowLen)
        case UInt32(Character(":").asciiValue!):
            // Basic colon commands (mocked)
            state.statusMessage = ":"
        case UInt32(Character("w").asciiValue!):
            // Very simple :w shortcut if : was pressed (heuristic)
            if state.statusMessage == ":" {
                 state.saveFile()
            }
        default: break
        }
        ensureEditorVisible(state, contentRows: contentRows, availWidth: availWidth)
        return true
    }

    switch k.keyCode {
    case Key.down.rawValue:
        if k.modifiers.contains(.alt) {
            // Alt+Down: move page down
            state.cursorRow = min(state.cursorRow + contentRows, max(0, state.fileContent.count - 1))
            let rowLen = state.fileContent.isEmpty ? 0 : state.fileContent[state.cursorRow].count
            state.cursorCol = min(state.cursorCol, rowLen)
        } else {
            state.cursorRow = min(state.cursorRow + 1, max(0, state.fileContent.count - 1))
            let rowLen = state.fileContent.isEmpty ? 0 : state.fileContent[state.cursorRow].count
            state.cursorCol = min(state.cursorCol, rowLen)
        }
        ensureEditorVisible(state, contentRows: contentRows, availWidth: availWidth)
    case Key.up.rawValue:
        if k.modifiers.contains(.alt) {
            // Alt+Up: move page up
            state.cursorRow = max(state.cursorRow - contentRows, 0)
            let rowLen = state.fileContent.isEmpty ? 0 : state.fileContent[state.cursorRow].count
            state.cursorCol = min(state.cursorCol, rowLen)
        } else {
            state.cursorRow = max(state.cursorRow - 1, 0)
            let rowLen = state.fileContent.isEmpty ? 0 : state.fileContent[state.cursorRow].count
            state.cursorCol = min(state.cursorCol, rowLen)
        }
        ensureEditorVisible(state, contentRows: contentRows, availWidth: availWidth)
    case Key.left.rawValue:
        if k.modifiers.contains(.alt) || k.modifiers.contains(.ctrl) {
            jumpWordBackward(state: state)
        } else {
            state.cursorCol = max(state.cursorCol - 1, 0)
        }
    case Key.right.rawValue:
        if k.modifiers.contains(.alt) || k.modifiers.contains(.ctrl) {
            jumpWordForward(state: state)
        } else {
            let rowLen = state.fileContent.isEmpty ? 0 : state.fileContent[state.cursorRow].count
            state.cursorCol = min(state.cursorCol + 1, rowLen)
        }
    // ESC+b / ESC+f: macOS Terminal.app sends these for Option+Arrow (emacs-style word jump)
    case UInt32(Character("b").asciiValue!):
        if k.modifiers == .alt { jumpWordBackward(state: state) }
    case UInt32(Character("f").asciiValue!):
        if k.modifiers == .alt { jumpWordForward(state: state) }
    case 57356: // Home key
        state.cursorCol = 0
    case 57357: // End key
        let rowLen = state.fileContent.isEmpty ? 0 : state.fileContent[state.cursorRow].count
        state.cursorCol = rowLen
    case 57358: // Page Up
        state.cursorRow = max(state.cursorRow - contentRows, 0)
        let rowLen = state.fileContent.isEmpty ? 0 : state.fileContent[state.cursorRow].count
        state.cursorCol = min(state.cursorCol, rowLen)
        ensureEditorVisible(state, contentRows: contentRows, availWidth: availWidth)
    case 57359: // Page Down
        state.cursorRow = min(state.cursorRow + contentRows, max(0, state.fileContent.count - 1))
        let rowLen = state.fileContent.isEmpty ? 0 : state.fileContent[state.cursorRow].count
        state.cursorCol = min(state.cursorCol, rowLen)
        ensureEditorVisible(state, contentRows: contentRows, availWidth: availWidth)
    case Key.enter.rawValue, Key.enterAlt.rawValue:
        guard !state.fileContent.isEmpty else {
            state.fileContent = [""]
            state.cursorRow = 0
            state.cursorCol = 0
            return true
        }
        let currentLine = state.fileContent[state.cursorRow]
        let prefix = String(currentLine.prefix(state.cursorCol))
        let suffix = String(currentLine.dropFirst(state.cursorCol))
        state.fileContent[state.cursorRow] = prefix
        state.fileContent.insert(suffix, at: state.cursorRow + 1)
        state.cursorRow += 1
        state.cursorCol = 0
        ensureEditorVisible(state, contentRows: contentRows, availWidth: availWidth)
    case Key.backspace.rawValue, Key.backspaceAlt.rawValue:
        if state.cursorCol > 0 {
            var line = state.fileContent[state.cursorRow]
            let idx = line.index(line.startIndex, offsetBy: state.cursorCol - 1)
            line.remove(at: idx)
            state.fileContent[state.cursorRow] = line
            state.cursorCol -= 1
        } else if state.cursorRow > 0 {
            let line = state.fileContent.remove(at: state.cursorRow)
            state.cursorRow -= 1
            state.cursorCol = state.fileContent[state.cursorRow].count
            state.fileContent[state.cursorRow] += line
            ensureEditorVisible(state, contentRows: contentRows, availWidth: availWidth)
        }
    case UInt32(Character("g").asciiValue!): // g = go to top
        if k.modifiers == .shift { // G
            state.cursorRow = max(0, state.fileContent.count - 1)
            ensureEditorVisible(state, contentRows: contentRows, availWidth: availWidth)
        } else {
            state.cursorRow = 0
            state.cursorCol = 0
            state.scrollOffset = 0
        }
    default:
        if !k.associatedText.isEmpty {
            if state.fileContent.isEmpty { state.fileContent = [""] }
            var line = state.fileContent[state.cursorRow]
            let idx = line.index(line.startIndex, offsetBy: state.cursorCol)
            line.insert(contentsOf: k.associatedText, at: idx)
            state.fileContent[state.cursorRow] = line
            state.cursorCol += k.associatedText.count
        } else if k.keyCode < 256, let char = UnicodeScalar(k.keyCode).map(Character.init), char.isPrintable {
            if state.fileContent.isEmpty { state.fileContent = [""] }
            var line = state.fileContent[state.cursorRow]
            let idx = line.index(line.startIndex, offsetBy: state.cursorCol)
            line.insert(char, at: idx)
            state.fileContent[state.cursorRow] = line
            state.cursorCol += 1
        }
    }
    ensureEditorVisible(state, contentRows: contentRows, availWidth: availWidth)
    return true
}

extension Character {
    var isPrintable: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return !scalar.isASCII || (scalar.value >= 32 && scalar.value < 127)
    }
}

@MainActor
func jumpWordForward(state: EditorState) {
    guard !state.fileContent.isEmpty else { return }
    let line = state.fileContent[state.cursorRow]
    let chars = Array(line)
    
    guard state.cursorCol < chars.count else { return }
    
    var pos = state.cursorCol
    
    // Skip current word if in middle of word
    while pos < chars.count && !chars[pos].isWhitespace {
        pos += 1
    }
    
    // Skip whitespace
    while pos < chars.count && chars[pos].isWhitespace {
        pos += 1
    }
    
    state.cursorCol = min(pos, chars.count)
}

@MainActor
func jumpWordBackward(state: EditorState) {
    guard !state.fileContent.isEmpty else { return }
    let line = state.fileContent[state.cursorRow]
    let chars = Array(line)
    
    guard state.cursorCol > 0 else { return }
    
    var pos = max(0, state.cursorCol - 1)
    
    // Skip whitespace
    while pos > 0 && chars[pos].isWhitespace {
        pos -= 1
    }
    
    // Skip word
    while pos > 0 && !chars[pos].isWhitespace {
        pos -= 1
    }
    
    // Move to start of word if we skipped whitespace
    if pos > 0 && chars[pos].isWhitespace {
        pos += 1
    }
    
    state.cursorCol = pos
}

// MARK: - Helpers

func displayWidth(_ string: String) -> Int {
    return string.count // Simplified as emojis are removed
}

@MainActor
func handleMouse(_ m: MouseEvent, state: EditorState, pipeline: RenderPipeline) {
    let treeWidth = min(state.treePanelWidth, pipeline.columns / 2)
    let editorStart = 1 + treeWidth + 1  // 1 (title bar) + tree width + 1 (separator)
    let lineNumWidth = max(3, String(state.fileContent.count).count + 1)

    if m.button.isScroll {
        // Scroll events reset scrolling flag, then re-enable it
        state.isScrolling = true
        
        if m.col <= treeWidth {
            // Scroll tree
            if m.button == .scrollUp {
                state.treeScrollOffset = max(0, state.treeScrollOffset - 3)
            } else if m.button == .scrollDown {
                state.treeScrollOffset = min(max(0, state.flatTree.count - 1), state.treeScrollOffset + 3)
            }
        } else {
            // Scroll editor
            if m.button == .scrollUp {
                state.scrollOffset = max(0, state.scrollOffset - 3)
            } else if m.button == .scrollDown {
                state.scrollOffset = min(max(0, state.fileContent.count - 1), state.scrollOffset + 3)
            }
        }
    } else if m.kind == .press && m.button == .left {
        // Click event stops scrolling
        state.isScrolling = false
        let now = Date()
        let isDoubleClick = now.timeIntervalSince(state.lastClickTime) < 0.3

        // m.row is 1-based. row 1 is Title Bar. row 2 is first content row.
        let contentRow = m.row - 2 

        if m.col <= treeWidth && contentRow >= 0 {
            // Click in tree
            let clickIdx = state.treeScrollOffset + contentRow
            if clickIdx >= 0 && clickIdx < state.flatTree.count {
                if isDoubleClick && clickIdx == state.lastClickIndex {
                    // Double click action
                    let entry = state.flatTree[clickIdx].entry
                    if entry.isDirectory {
                        state.toggleExpand(at: clickIdx)
                    } else {
                        state.openFile(at: clickIdx)
                        state.cursorCol = 0
                    }
                } else {
                    state.selectedTreeIndex = clickIdx
                    state.mode = .tree
                }
                state.lastClickIndex = clickIdx
            }
        } else if contentRow >= 0 {
            // Click in editor
            let lineIdx = state.scrollOffset + contentRow
            if lineIdx >= 0 && lineIdx < state.fileContent.count {
                state.cursorRow = lineIdx
                state.mode = .editor
                let line = state.fileContent[lineIdx]
                let relativeCol = m.col - editorStart - lineNumWidth
                if state.config.wrapLines {
                    state.cursorCol = min(max(0, relativeCol), line.count)
                } else {
                    state.cursorCol = min(max(0, relativeCol + state.hScrollOffset), line.count)
                }
            }
        }
        state.lastClickTime = now
    } else if m.kind == .motion {
        // Ignore mouse motion (hover) to save energy until a click
        return
    }
}

@MainActor
func ensureTreeVisible(_ state: EditorState, contentRows: Int = 20) {
    state.selectedTreeIndex = max(0, state.selectedTreeIndex)
    if state.selectedTreeIndex < state.treeScrollOffset {
        state.treeScrollOffset = state.selectedTreeIndex
    } else if state.selectedTreeIndex >= state.treeScrollOffset + contentRows {
        state.treeScrollOffset = max(0, state.selectedTreeIndex - contentRows + 1)
    }
}

@MainActor
func ensureEditorVisible(_ state: EditorState, contentRows: Int = 20, availWidth: Int = 80) {
    state.cursorRow = max(0, state.cursorRow)
    if state.cursorRow < state.scrollOffset {
        state.scrollOffset = state.cursorRow
    } else if state.cursorRow >= state.scrollOffset + contentRows {
        state.scrollOffset = max(0, state.cursorRow - contentRows + 1)
    }

    if !state.config.wrapLines {
        if state.cursorCol < state.hScrollOffset {
            state.hScrollOffset = state.cursorCol
        } else if state.cursorCol >= state.hScrollOffset + availWidth {
            state.hScrollOffset = max(0, state.cursorCol - availWidth + 1)
        }
    } else {
        state.hScrollOffset = 0
    }
}

// MARK: - Main

@main
struct KittyCodeEntry {
    static func main() async {
        do {
            try await runEditor()
        } catch {
            let msg = "CRASH: \(error)\n"
            try? msg.write(toFile: "/tmp/kittycode-crash.log", atomically: true, encoding: .utf8)
            FileHandle.standardError.write(Data(msg.utf8))
        }
    }

    @MainActor static func runEditor() async throws {
        let args = CommandLine.arguments
        let rootPath: String
        if args.count > 1 {
            rootPath = args[1]
        } else {
            rootPath = FileManager.default.currentDirectoryPath
        }

        let config = KittyConfig.load()
        let state = EditorState(rootPath: rootPath, config: config)
        let connection = POSIXTerminalConnection()
        let runtime = ApplicationRuntime(connection: connection)

        try await runtime.run(
            render: { pipeline in
                pipeline.buffer.clear()
                render(pipeline: pipeline, state: state)
            },
            onEvent: { event, pipeline in
                let cont = handleEvent(event: event, state: state, pipeline: pipeline)
                if cont {
                    pipeline.buffer.clear()
                    render(pipeline: pipeline, state: state)
                }
                return cont
            }
        )
    }
}

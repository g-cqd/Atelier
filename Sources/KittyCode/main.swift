import Foundation
import KittyApp
import KittyWidgets
import KittyCodecs
import KittyInput
import KittyRenderer
import KittyTerminal

// MARK: - File Tree Model

struct FileEntry: Sendable {
    let name: String
    let path: String
    let isDirectory: Bool
    var children: [FileEntry]
    var isExpanded: Bool

    var icon: String {
        if isDirectory {
            return isExpanded ? "▼ 📁" : "▶ 📁"
        }
        let ext = (name as NSString).pathExtension
        switch ext {
        case "swift": return "  🟠"
        case "json": return "  📋"
        case "md": return "  📝"
        case "scm": return "  🔍"
        default: return "  📄"
        }
    }
}

// MARK: - Editor State

@MainActor
final class EditorState {
    var rootPath: String
    var fileTree: [FileEntry] = []
    var flatTree: [(depth: Int, entry: FileEntry)] = []
    var selectedTreeIndex: Int = 0
    var treeScrollOffset: Int = 0

    var fileContent: [String] = []
    var fileName: String = ""
    var filePath: String = ""
    var scrollOffset: Int = 0
    var cursorRow: Int = 0

    var treePanelWidth: Int = 30
    var statusMessage: String = ""
    var mode: Mode = .tree

    enum Mode { case tree, editor }

    init(rootPath: String) {
        self.rootPath = rootPath
        self.fileTree = Self.scanDirectory(rootPath, maxDepth: 1)
        self.flatTree = Self.flatten(fileTree)
        self.statusMessage = "Opened: \(rootPath)"
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
        cursorRow = 0
        mode = .editor
        statusMessage = entry.name
    }
}

// MARK: - Styles

let colorScheme = (
    bg: Style(bg: .rgb(r: 30, g: 30, b: 30)),
    treeBg: Style(fg: .rgb(r: 204, g: 204, b: 204), bg: .rgb(r: 24, g: 24, b: 24)),
    treeSelected: Style(fg: .rgb(r: 255, g: 255, b: 255), bg: .rgb(r: 38, g: 79, b: 120)),
    treeDir: Style(fg: .rgb(r: 129, g: 199, b: 132), bg: .rgb(r: 24, g: 24, b: 24), bold: true),
    lineNumber: Style(fg: .rgb(r: 100, g: 100, b: 100), bg: .rgb(r: 30, g: 30, b: 30)),
    editorText: Style(fg: .rgb(r: 212, g: 212, b: 212), bg: .rgb(r: 30, g: 30, b: 30)),
    editorCursorLine: Style(fg: .rgb(r: 212, g: 212, b: 212), bg: .rgb(r: 40, g: 40, b: 40)),
    statusBar: Style(fg: .rgb(r: 255, g: 255, b: 255), bg: .rgb(r: 0, g: 122, b: 204)),
    titleBar: Style(fg: .rgb(r: 204, g: 204, b: 204), bg: .rgb(r: 50, g: 50, b: 50)),
    separator: Style(fg: .rgb(r: 60, g: 60, b: 60), bg: .rgb(r: 30, g: 30, b: 30))
)

// MARK: - Render

@MainActor
func render(pipeline: RenderPipeline, state: EditorState) {
    let cols = pipeline.columns
    let rows = pipeline.rows
    guard cols > 0 && rows > 2 else { return }

    let treeWidth = min(state.treePanelWidth, cols / 2)
    let editorStart = treeWidth + 1
    let editorWidth = cols - editorStart
    let contentRows = rows - 2 // title bar + status bar

    // Title bar
    let title = " KittyCode — \(state.rootPath) "
    let titlePad = String(repeating: " ", count: max(0, cols - title.count))
    pipeline.buffer.write(String((title + titlePad).prefix(cols)), row: 0, col: 0, style: colorScheme.titleBar)

    // File tree panel
    for r in 0..<contentRows {
        let treeIdx = state.treeScrollOffset + r
        if treeIdx < state.flatTree.count {
            let (depth, entry) = state.flatTree[treeIdx]
            let indent = String(repeating: " ", count: depth * 2)
            let label = indent + entry.icon + " " + entry.name
            let padded = label + String(repeating: " ", count: max(0, treeWidth - label.count))
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
            pipeline.buffer.write(String(repeating: " ", count: treeWidth), row: r + 1, col: 0, style: colorScheme.treeBg)
        }

        // Separator
        pipeline.buffer.write("│", row: r + 1, col: treeWidth, style: colorScheme.separator)
    }

    // Editor panel
    let lineNumWidth = max(3, String(state.fileContent.count).count + 1)

    if state.fileContent.isEmpty {
        // Empty state
        let msg = "Open a file from the tree (Enter)"
        let msgRow = contentRows / 2
        for r in 0..<contentRows {
            if r == msgRow {
                let pad = max(0, (editorWidth - msg.count) / 2)
                let line = String(repeating: " ", count: pad) + msg + String(repeating: " ", count: max(0, editorWidth - pad - msg.count))
                pipeline.buffer.write(String(line.prefix(editorWidth)), row: r + 1, col: editorStart, style: Style(fg: .rgb(r: 100, g: 100, b: 100), bg: .rgb(r: 30, g: 30, b: 30)))
            } else {
                pipeline.buffer.write(String(repeating: " ", count: editorWidth), row: r + 1, col: editorStart, style: colorScheme.editorText)
            }
        }
    } else {
        for r in 0..<contentRows {
            let lineIdx = state.scrollOffset + r
            let isCurrentLine = lineIdx == state.cursorRow

            if lineIdx < state.fileContent.count {
                // Line number
                let numStr = String(lineIdx + 1)
                let numPad = String(repeating: " ", count: max(0, lineNumWidth - numStr.count - 1))
                pipeline.buffer.write(numPad + numStr + " ", row: r + 1, col: editorStart, style: colorScheme.lineNumber)

                // Line content
                let line = state.fileContent[lineIdx]
                let textStyle = isCurrentLine ? colorScheme.editorCursorLine : colorScheme.editorText
                let availWidth = editorWidth - lineNumWidth
                let displayLine = String(line.prefix(availWidth))
                let pad = String(repeating: " ", count: max(0, availWidth - displayLine.count))
                pipeline.buffer.write(displayLine + pad, row: r + 1, col: editorStart + lineNumWidth, style: textStyle)
            } else {
                // Past end of file
                pipeline.buffer.write("~" + String(repeating: " ", count: editorWidth - 1), row: r + 1, col: editorStart, style: colorScheme.lineNumber)
            }
        }
    }

    // Status bar
    let modeStr = state.mode == .tree ? "TREE" : "EDIT"
    let posStr = state.fileContent.isEmpty ? "" : "Ln \(state.cursorRow + 1)/\(state.fileContent.count)"
    let statusLeft = " [\(modeStr)] \(state.statusMessage)"
    let statusRight = "\(posStr)  \(cols)x\(rows) "
    let statusPad = max(0, cols - statusLeft.count - statusRight.count)
    let statusLine = statusLeft + String(repeating: " ", count: statusPad) + statusRight
    pipeline.buffer.write(String(statusLine.prefix(cols)), row: rows - 1, col: 0, style: colorScheme.statusBar)
}

// MARK: - Event Handling

@MainActor
func handleEvent(event: InputEvent, state: EditorState, pipeline: RenderPipeline) -> Bool {
    let contentRows = pipeline.rows - 2

    switch event {
    case .key(let k):
        // Global: ESC goes back to tree mode, q quits from tree mode
        if k.keyCode == 27 { // ESC
            if state.mode == .editor {
                state.mode = .tree
                state.statusMessage = state.fileName.isEmpty ? "Ready" : state.fileName
                return true
            } else {
                return false // quit
            }
        }
        if k.keyCode == 3 { return false } // Ctrl+C

        switch state.mode {
        case .tree:
            return handleTreeKey(k, state: state, contentRows: contentRows)
        case .editor:
            return handleEditorKey(k, state: state, contentRows: contentRows)
        }

    case .mouse(let m):
        handleMouse(m, state: state, pipeline: pipeline)
        return true

    default:
        return true
    }
}

@MainActor
func handleTreeKey(_ k: KeyEvent, state: EditorState, contentRows: Int) -> Bool {
    switch k.keyCode {
    case UInt32(Character("q").asciiValue!):
        if k.modifiers.isEmpty { return false }
    case UInt32(Character("j").asciiValue!), 66: // j or down arrow (CSI B = 66)
        state.selectedTreeIndex = min(state.selectedTreeIndex + 1, state.flatTree.count - 1)
        ensureTreeVisible(state, contentRows: contentRows)
    case UInt32(Character("k").asciiValue!), 65: // k or up arrow
        state.selectedTreeIndex = max(state.selectedTreeIndex - 1, 0)
        ensureTreeVisible(state, contentRows: contentRows)
    case 13, 10: // Enter
        let entry = state.flatTree[state.selectedTreeIndex].entry
        if entry.isDirectory {
            state.toggleExpand(at: state.selectedTreeIndex)
        } else {
            state.openFile(at: state.selectedTreeIndex)
        }
    case UInt32(Character("l").asciiValue!), 67: // l or right arrow — expand or enter
        let entry = state.flatTree[state.selectedTreeIndex].entry
        if entry.isDirectory && !entry.isExpanded {
            state.toggleExpand(at: state.selectedTreeIndex)
        } else if !entry.isDirectory {
            state.openFile(at: state.selectedTreeIndex)
        }
    case UInt32(Character("h").asciiValue!), 68: // h or left arrow — collapse
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
func handleEditorKey(_ k: KeyEvent, state: EditorState, contentRows: Int) -> Bool {
    switch k.keyCode {
    case UInt32(Character("j").asciiValue!), 66: // j or down
        state.cursorRow = min(state.cursorRow + 1, state.fileContent.count - 1)
        ensureEditorVisible(state, contentRows: contentRows)
    case UInt32(Character("k").asciiValue!), 65: // k or up
        state.cursorRow = max(state.cursorRow - 1, 0)
        ensureEditorVisible(state, contentRows: contentRows)
    case UInt32(Character("g").asciiValue!): // g = go to top
        state.cursorRow = 0
        state.scrollOffset = 0
    case UInt32(Character("G").asciiValue!): // G = go to bottom
        state.cursorRow = max(0, state.fileContent.count - 1)
        ensureEditorVisible(state, contentRows: contentRows)
    default:
        break
    }
    return true
}

@MainActor
func handleMouse(_ m: MouseEvent, state: EditorState, pipeline: RenderPipeline) {
    let treeWidth = min(state.treePanelWidth, pipeline.columns / 2)

    if m.button.isScroll {
        if m.col <= treeWidth {
            // Scroll tree
            if m.button == .scrollUp {
                state.treeScrollOffset = max(0, state.treeScrollOffset - 3)
            } else if m.button == .scrollDown {
                state.treeScrollOffset = min(max(0, state.flatTree.count - 5), state.treeScrollOffset + 3)
            }
        } else {
            // Scroll editor
            if m.button == .scrollUp {
                state.scrollOffset = max(0, state.scrollOffset - 3)
            } else if m.button == .scrollDown {
                state.scrollOffset = min(max(0, state.fileContent.count - 5), state.scrollOffset + 3)
            }
        }
    } else if m.kind == .press && m.button == .left {
        if m.col <= treeWidth && m.row > 0 {
            // Click in tree
            let clickIdx = state.treeScrollOffset + m.row - 1
            if clickIdx < state.flatTree.count {
                state.selectedTreeIndex = clickIdx
                state.mode = .tree
            }
        } else if m.row > 0 {
            // Click in editor
            let lineIdx = state.scrollOffset + m.row - 1
            if lineIdx < state.fileContent.count {
                state.cursorRow = lineIdx
                state.mode = .editor
            }
        }
    }
}

@MainActor
func ensureTreeVisible(_ state: EditorState, contentRows: Int = 20) {
    if state.selectedTreeIndex < state.treeScrollOffset {
        state.treeScrollOffset = state.selectedTreeIndex
    } else if state.selectedTreeIndex >= state.treeScrollOffset + contentRows {
        state.treeScrollOffset = state.selectedTreeIndex - contentRows + 1
    }
}

@MainActor
func ensureEditorVisible(_ state: EditorState, contentRows: Int = 20) {
    if state.cursorRow < state.scrollOffset {
        state.scrollOffset = state.cursorRow
    } else if state.cursorRow >= state.scrollOffset + contentRows {
        state.scrollOffset = state.cursorRow - contentRows + 1
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

        let state = EditorState(rootPath: rootPath)
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

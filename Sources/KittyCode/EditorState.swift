import Foundation
import KittyCodecs

@MainActor
final class EditorState {
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

    enum Mode {
        case tree
        case editor
    }

    enum VimMode {
        case normal
        case insert
    }

    var config: KittyConfig
    var colorScheme: ColorScheme
    var rootPath: String
    var fileTree: [FileEntry] = []
    var flatTree: [(depth: Int, entry: FileEntry)] = []
    var selectedTreeIndex = 0
    var treeScrollOffset = 0
    var fileContent: [String] = []
    var fileName = ""
    var filePath = ""
    var scrollOffset = 0
    var hScrollOffset = 0
    var cursorRow = 0
    var cursorCol = 0
    var treePanelWidth = 30
    var statusMessage = ""
    var mode: Mode = .tree
    var vimMode: VimMode = .normal
    var lastClickTime: Date = .distantPast
    var lastClickIndex = -1
    var isScrolling = false

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
        let theme = config.theme
        return ColorScheme(
            bg: Style(bg: theme.backgroundColor.color),
            treeBg: Style(fg: theme.treePanelForeground.color, bg: theme.treePanelBackground.color),
            treeSelected: Style(fg: theme.treeSelectedForeground.color, bg: theme.treeSelectedBackground.color),
            treeDir: Style(fg: .rgb(r: 0x81, g: 0xc7, b: 0x84), bg: theme.treePanelBackground.color, bold: true),
            lineNumber: Style(fg: .rgb(r: 0x64, g: 0x64, b: 0x64), bg: theme.backgroundColor.color),
            editorText: Style(fg: theme.editorForeground.color, bg: theme.backgroundColor.color),
            editorCursorLine: Style(fg: theme.editorForeground.color, bg: theme.editorCursorLineBackground.color),
            statusBar: Style(fg: theme.statusBarForeground.color, bg: theme.statusBarBackground.color),
            titleBar: Style(fg: theme.titleBarForeground.color, bg: theme.titleBarBackground.color),
            separator: Style(fg: .rgb(r: 0x3c, g: 0x3c, b: 0x3c), bg: theme.backgroundColor.color)
        )
    }

    static func scanDirectory(_ path: String, maxDepth: Int) -> [FileEntry] {
        let fileManager = FileManager.default
        guard let items = try? fileManager.contentsOfDirectory(atPath: path) else {
            return []
        }

        var entries: [FileEntry] = []
        for item in items.sorted() where !item.hasPrefix(".") {
            let fullPath = (path as NSString).appendingPathComponent(item)
            var isDirectory: ObjCBool = false
            fileManager.fileExists(atPath: fullPath, isDirectory: &isDirectory)
            var children: [FileEntry] = []
            if isDirectory.boolValue && maxDepth > 0 {
                children = scanDirectory(fullPath, maxDepth: maxDepth - 1)
            }
            entries.append(
                FileEntry(
                    name: item,
                    path: fullPath,
                    isDirectory: isDirectory.boolValue,
                    children: children,
                    isExpanded: false
                )
            )
        }

        return entries.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
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
        for index in entries.indices {
            if entries[index].path == path {
                entries[index].isExpanded.toggle()
                if entries[index].isExpanded && entries[index].children.isEmpty {
                    entries[index].children = Self.scanDirectory(entries[index].path, maxDepth: 1)
                }
                return
            }
            if entries[index].isDirectory {
                toggleInTree(&entries[index].children, path: path)
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
import Foundation
public import KittyCodecs
import KittyFileTree
import KittyWorkspace

extension EditorState {
    public var activeFileDisplayName: String {
        fileName.isEmpty ? "Untitled" : fileName
    }

    public var contextHintText: String? {
        guard config.statusBar.showContextHints else { return nil }

        if let contextMenu {
            guard !contextMenu.items.isEmpty else { return "Esc Close" }
            let selectedIndex = min(max(0, contextMenu.selectedIndex), contextMenu.items.count - 1)
            let selectedItem = contextMenu.items[selectedIndex]
            let shortcut = selectedItem.shortcut.isEmpty ? "" : "\(selectedItem.shortcut)  "
            return "\(shortcut)Enter \(selectedItem.title)  Esc Close  ↑↓ Navigate"
        }

        if prompt != nil {
            let label = prompt?.submitLabel ?? "Confirm"
            return "Enter \(label)  Esc Cancel"
        }

        if vimCommandLine != nil {
            return "Enter Execute  Esc Cancel"
        }

        if mode == .searchPanel {
            return "Enter Select  \u{2191}\u{2193} Navigate  Esc Close"
        }

        if inFileSearch != nil {
            return "Enter Next  \u{2191}\u{2193} Navigate  Esc Close"
        }

        return nil
    }

    public func dismissContextMenu() {
        contextMenu = nil
    }

    public func showTreeContextMenu(at index: Int) {
        guard index >= 0, index < cachedFlatTree.count else { return }

        selectedTreeIndex = index
        let entry = cachedFlatTree[index].node
        noteSelectedPath(entry.path, isDirectory: entry.isDirectory)

        let resolver = KeymapResolver(config: config)
        let saveLabel = resolver.shortcutLabel(for: .saveFile) ?? ""

        let items: [ContextMenuItem]
        if entry.isDirectory {
            let toggleTitle = entry.isExpanded ? "Collapse Folder" : "Expand Folder"
            items = [
                ContextMenuItem(
                    title: toggleTitle, shortcut: "Enter", action: .toggleSelectedDirectory),
                ContextMenuItem(
                    title: "New File…", shortcut: "",
                    action: .beginCreateFile(inDirectory: entry.path)),
                ContextMenuItem(
                    title: "New Folder…", shortcut: "",
                    action: .beginCreateDirectory(inDirectory: entry.path)),
                ContextMenuItem(
                    title: "Rename…", shortcut: "", action: .beginRename(path: entry.path)),
                ContextMenuItem(
                    title: "Duplicate…", shortcut: "", action: .beginDuplicate(path: entry.path)),
                ContextMenuItem(title: "Move…", shortcut: "", action: .beginMove(path: entry.path)),
                ContextMenuItem(
                    title: "Delete…", shortcut: "", action: .beginDelete(path: entry.path)),
                ContextMenuItem(
                    title: "Save Here…", shortcut: saveLabel,
                    action: .beginSavePrompt(inDirectory: entry.path))
            ]
        } else {
            let directory = URL(fileURLWithPath: entry.path).deletingLastPathComponent().path
            items = [
                ContextMenuItem(title: "Open", shortcut: "Enter", action: .openSelected),
                ContextMenuItem(title: "Open and Pin", shortcut: "", action: .openSelectedPinned),
                ContextMenuItem(
                    title: "Rename…", shortcut: "", action: .beginRename(path: entry.path)),
                ContextMenuItem(
                    title: "Duplicate…", shortcut: "", action: .beginDuplicate(path: entry.path)),
                ContextMenuItem(title: "Move…", shortcut: "", action: .beginMove(path: entry.path)),
                ContextMenuItem(
                    title: "Delete…", shortcut: "", action: .beginDelete(path: entry.path)),
                ContextMenuItem(
                    title: "Save Here…", shortcut: saveLabel,
                    action: .beginSavePrompt(inDirectory: directory))
            ]
        }

        contextMenu = ContextMenuState(
            title: entry.name,
            subtitle: relativePathForPrompt(entry.path),
            target: .treeNode(index: index),
            items: items
        )
    }

    public func showEditorContextMenu() {
        let saveDirectory = lastSelectedDirectoryPath ?? rootPath
        let resolver = KeymapResolver(config: config)
        var items: [ContextMenuItem] = []
        if bufferManager.activeBuffer?.editHistory.hasUndo == true {
            items.append(
                ContextMenuItem(
                    title: "Undo", shortcut: resolver.shortcutLabel(for: .undo) ?? "",
                    action: .undo))
        }
        if bufferManager.activeBuffer?.editHistory.hasRedo == true {
            items.append(
                ContextMenuItem(
                    title: "Redo", shortcut: resolver.shortcutLabel(for: .redo) ?? "",
                    action: .redo))
        }
        items += [
            ContextMenuItem(
                title: "Save", shortcut: resolver.shortcutLabel(for: .saveFile) ?? "",
                action: .saveFile),
            ContextMenuItem(
                title: "Save As…", shortcut: "",
                action: .beginSavePrompt(inDirectory: saveDirectory)),
            ContextMenuItem(
                title: "Focus Explorer",
                shortcut: resolver.shortcutLabel(for: .escapeEditor) ?? "", action: .focusTree),
            ContextMenuItem(
                title: "Close Tab", shortcut: resolver.shortcutLabel(for: .closeTab) ?? "",
                action: .closeTab)
        ]
        contextMenu = ContextMenuState(
            title: activeFileDisplayName,
            subtitle: currentLanguage ?? "plain text",
            target: .editor,
            items: items
        )
    }

    public func handleContextMenuKey(_ key: KeyEvent) -> Bool {
        guard var contextMenu else { return false }

        switch key.keyCode {
            case Key.up.rawValue:
                contextMenu.selectedIndex = max(0, contextMenu.selectedIndex - 1)
                self.contextMenu = contextMenu
                return true
            case Key.down.rawValue:
                contextMenu.selectedIndex = min(
                    contextMenu.items.count - 1, contextMenu.selectedIndex + 1)
                self.contextMenu = contextMenu
                return true
            case Key.enter.rawValue, Key.enterAlt.rawValue:
                performContextMenuAction(contextMenu.items[contextMenu.selectedIndex].action)
                return true
            case AsciiKey.escape:
                dismissContextMenu()
                return true
            default:
                return true
        }
    }

    public func performContextMenuSelection(at index: Int) {
        guard var contextMenu else { return }
        guard index >= 0, index < contextMenu.items.count else { return }
        contextMenu.selectedIndex = index
        self.contextMenu = contextMenu
        performContextMenuAction(contextMenu.items[index].action)
    }

    public func contextMenuMoveUp() {
        guard var contextMenu else { return }
        contextMenu.selectedIndex = max(0, contextMenu.selectedIndex - 1)
        self.contextMenu = contextMenu
    }

    public func contextMenuMoveDown() {
        guard var contextMenu else { return }
        contextMenu.selectedIndex = min(contextMenu.items.count - 1, contextMenu.selectedIndex + 1)
        self.contextMenu = contextMenu
    }

    public func contextMenuConfirm() {
        guard let contextMenu else { return }
        performContextMenuAction(contextMenu.items[contextMenu.selectedIndex].action)
    }

    public func performContextMenuAction(_ action: ContextMenuAction) {
        dismissContextMenu()

        switch action {
            case .undo:
                performUndo()
            case .redo:
                performRedo()
            case .openSelected:
                guard selectedTreeIndex >= 0, selectedTreeIndex < cachedFlatTree.count else { return }
                openFile(at: selectedTreeIndex)
                cursorCol = 0
                mode = .editor
            case .openSelectedPinned:
                guard selectedTreeIndex >= 0, selectedTreeIndex < cachedFlatTree.count else { return }
                openFile(at: selectedTreeIndex)
                cursorCol = 0
                if let buffer = bufferManager.activeBuffer, buffer.isPreview {
                    buffer.isPreview = false
                }
                mode = .editor
            case .toggleSelectedDirectory:
                guard selectedTreeIndex >= 0, selectedTreeIndex < cachedFlatTree.count else { return }
                toggleExpand(at: selectedTreeIndex)
            case .beginCreateFile(let directory):
                lastSelectedDirectoryPath = directory
                beginCreateFilePrompt(in: directory)
            case .beginCreateDirectory(let directory):
                lastSelectedDirectoryPath = directory
                beginCreateDirectoryPrompt(in: directory)
            case .beginSavePrompt(let directory):
                lastSelectedDirectoryPath = directory
                beginSavePrompt(suggestedPath: directorySuggestion(for: directory))
            case .beginRename(let path):
                beginRenamePrompt(for: path)
            case .beginDuplicate(let path):
                beginDuplicatePrompt(for: path)
            case .beginMove(let path):
                beginMovePrompt(for: path)
            case .beginDelete(let path):
                beginDeletePrompt(for: path)
            case .saveFile:
                saveFile()
            case .focusTree:
                mode = .tree
            case .closeTab:
                closeCurrentTab()
        }
    }

    private func directorySuggestion(for directory: String) -> String {
        let relativePath = relativePathForPrompt(directory)
        if relativePath.isEmpty || relativePath == "." {
            return ""
        }
        return relativePath.hasSuffix("/") ? relativePath : relativePath + "/"
    }
}

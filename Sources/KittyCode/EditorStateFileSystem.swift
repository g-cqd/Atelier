import Foundation

extension EditorState {
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
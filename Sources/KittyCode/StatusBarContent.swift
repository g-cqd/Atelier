import Foundation

extension EditorState {
    private static let statusBarSeparator = " │ "

    func statusBarSegments(columns: Int, rows: Int) -> (left: String, right: String) {
        let left = joinStatusBarSegments(config.statusBar.leftItems.compactMap(statusBarText(for:)))
        var rightSegments = config.statusBar.rightItems.compactMap(statusBarText(for:))
        if let contextHintText {
            rightSegments.append(contextHintText)
        }
        let right = joinStatusBarSegments(rightSegments)
        return (left, right)
    }

    private func joinStatusBarSegments(_ segments: [String]) -> String {
        segments.joined(separator: Self.statusBarSeparator)
    }

    private func statusBarText(for item: KittyConfig.StatusBarConfig.Item) -> String? {
        switch item {
        case .path:
            return statusBarPath
        case .file:
            var label = activeFileDisplayName
            if bufferManager.activeBuffer?.isDirty == true {
                label += " *"
            }
            return label
        case .status:
            return condensedStatusMessage
        case .language:
            return currentLanguage ?? "plain text"
        case .size:
            return ByteCountFormatter.string(
                fromByteCount: Int64(serializedByteCount), countStyle: .file)
        case .lineEnding:
            return currentLineEnding.label
        case .git:
            return gitDiffStatText
        case .position:
            guard mode == .editor else { return nil }
            return "Ln \(cursorRow + 1), Col \(cursorCol + 1)"
        case .visibility:
            return fileVisibility.label
        }
    }

    private var condensedStatusMessage: String? {
        if prompt != nil || contextMenu != nil {
            return nil
        }

        if isLoadingGrammar {
            return "Loading grammar…"
        }

        guard !statusMessage.isEmpty else { return nil }
        let hiddenPrefixes = [
            "Opened ",
            "Ready |",
            "New file |",
            "-- NORMAL --",
            "-- INSERT --",
        ]

        if hiddenPrefixes.contains(where: statusMessage.hasPrefix) {
            return nil
        }

        return statusMessage
    }

    private var statusBarPath: String {
        // When focused on tree or no file open, show the working directory name
        if mode == .tree || fileName.isEmpty {
            return (rootPath as NSString).lastPathComponent
        }

        // Show relative path from rootPath, with dirty indicator
        let relative: String
        if filePath.hasPrefix(rootPath + "/") {
            relative = String(filePath.dropFirst(rootPath.count + 1))
        } else {
            relative = fileName
        }

        var label = Self.truncatePath(relative, maxComponents: 4)
        if bufferManager.activeBuffer?.isDirty == true {
            label += " *"
        }
        return label
    }

    /// Truncates a relative path to at most `maxComponents`, replacing leading
    /// components with "…" when necessary.
    ///
    /// Examples (maxComponents: 3):
    ///   "a/b/c/d/e.swift" → "…/c/d/e.swift"
    ///   "a/b.swift"       → "a/b.swift"
    static func truncatePath(_ path: String, maxComponents: Int) -> String {
        let components = path.split(separator: "/")
        guard components.count > maxComponents else { return path }
        let kept = components.suffix(maxComponents)
        return "…/" + kept.joined(separator: "/")
    }

    private var gitDiffStatText: String? {
        guard config.git.enabled, let provider = fileStatusProvider else { return nil }
        let summary = provider.summary
        guard !summary.isEmpty else { return nil }

        var parts: [String] = []
        if summary.modified > 0 {
            parts.append("M\(summary.modified)")
        }
        if summary.added > 0 {
            parts.append("A\(summary.added)")
        }
        if summary.untracked > 0 {
            parts.append("?\(summary.untracked)")
        }
        if summary.deleted > 0 {
            parts.append("D\(summary.deleted)")
        }
        if summary.conflicted > 0 {
            parts.append("!\(summary.conflicted)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

import Foundation

extension EditorState {
    func statusBarSegments(columns: Int, rows: Int) -> (left: String, right: String) {
        let left = config.statusBar.leftItems
            .compactMap(statusBarText(for:))
            .joined(separator: "  ")
        var rightSegments = config.statusBar.rightItems.compactMap(statusBarText(for:))
        if let contextHintText {
            rightSegments.append(contextHintText)
        }
        let right = rightSegments.joined(separator: "  ")
        return (left, right)
    }

    private func statusBarText(for item: KittyConfig.StatusBarConfig.Item) -> String? {
        switch item {
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
            return ByteCountFormatter.string(fromByteCount: Int64(serializedByteCount), countStyle: .file)
        case .lineEnding:
            return currentLineEnding.label
        case .git:
            return gitDiffStatText
        case .position:
            guard mode == .editor else { return nil }
            return "Ln \(cursorRow + 1), Col \(cursorCol + 1)"
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

    private var gitDiffStatText: String? {
        guard config.showGitStatus, let provider = fileStatusProvider else { return nil }
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

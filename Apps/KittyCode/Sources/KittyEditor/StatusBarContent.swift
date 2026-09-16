import AtelierText
import Foundation
import KittyFileTree
import KittyWorkspace
import System

extension EditorState {
    private static let statusBarSeparator = " │ "

    public func statusBarSegments(columns: Int, rows: Int) -> (left: String, right: String) {
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
            case .undo:
                return undoRedoIndicator
        }
    }

    private var condensedStatusMessage: String? {
        if prompt != nil || contextMenu != nil {
            return nil
        }

        // Command feedback takes priority when not expired
        if let feedback = commandFeedback, let expiry = commandFeedbackExpiry {
            if ContinuousClock.now < expiry {
                return feedback
            }
            // Otherwise will be cleared on next render cycle.
        }

        if let search = inFileSearch, search.pattern != nil {
            return search.totalCount == 0
                ? "No matches"
                : "Match \(search.activeMatchIndex + 1)/\(search.totalCount)"
        }

        if isLoadingGrammar {
            return "Loading grammar…"
        }

        guard !statusMessage.isEmpty else { return nil }
        let hiddenPrefixes = [
            "Opened ",
            "Ready |",
            "New file |"
        ]

        // Show vim mode indicators when in vim keybinding mode
        if config.keybindingMode == .vim {
            if statusMessage == "-- NORMAL --" || statusMessage == "-- INSERT --" {
                return statusMessage
            }
        }

        if hiddenPrefixes.contains(where: statusMessage.hasPrefix) {
            return nil
        }

        // Still hide vim mode indicators for non-vim modes
        if statusMessage == "-- NORMAL --" || statusMessage == "-- INSERT --" {
            return nil
        }

        return statusMessage
    }

    private var undoRedoIndicator: String? {
        guard mode == .editor else {
            let hasUndo = fileTreeHistory.hasUndo
            let hasRedo = fileTreeHistory.hasRedo
            guard hasUndo || hasRedo else { return nil }
            var indicator = "U:\(hasUndo ? "yes" : "no") R:\(hasRedo ? "yes" : "no")"
            if let nextUndo = fileTreeHistory.peekUndo {
                indicator += " (\(nextUndo.description))"
            }
            return indicator
        }
        let hasUndo = bufferManager.activeBuffer?.editHistory.hasUndo ?? false
        let hasRedo = bufferManager.activeBuffer?.editHistory.hasRedo ?? false
        guard hasUndo || hasRedo else { return nil }
        return "U:\(hasUndo ? "yes" : "no") R:\(hasRedo ? "yes" : "no")"
    }

    private var statusBarPath: String {
        // When focused on tree or no file open, show the working directory name
        if mode == .tree || fileName.isEmpty {
            return FilePath(rootPath).lastComponent?.string ?? rootPath
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
    public static func truncatePath(_ path: String, maxComponents: Int) -> String {
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

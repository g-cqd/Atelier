import DiffCore
import DiffGit
import DiffRendering
import Foundation

/// What the window shows about the comparison as a whole: its title, its totals, and the configuration it could be
/// reopened with. Derived from package-visible state only, so it lives apart from the model's mutations.
extension DiffViewerModel {
    /// Lines added and removed, over the file list when it is showing and over the selected file otherwise.
    package var totals: DiffTotals {
        if isShowingCombinedFiles {
            DiffTotals(
                files: changedPathCount,
                added: renderedFiles.reduce(0) { $0 + $1.rendered.addedLines },
                removed: renderedFiles.reduce(0) { $0 + $1.rendered.removedLines },
                coversEveryFile: renderedFiles.count == changedPathCount
            )
        } else {
            DiffTotals(
                files: changedPathCount, added: rendered?.addedLines ?? 0, removed: rendered?.removedLines ?? 0,
                coversEveryFile: false)
        }
    }

    /// The comparison the sides make up, when they form one a window could be opened with again; nil while a side
    /// is empty or the two sides do not belong together.
    package var currentConfiguration: LaunchConfiguration? {
        switch (left.source, right.source) {
            case (.gitRef(let repository, let leftRef), .directory(let folder))
            where repository.standardizedFileURL == folder.standardizedFileURL:
                .repository(repository, leftRef: leftRef, rightRef: nil)
            case (.gitRef(let repository, let leftRef), .gitRef(let other, let rightRef)) where repository == other:
                .repository(repository, leftRef: leftRef, rightRef: rightRef)
            case (.file(let left), .file(let right)), (.directory(let left), .directory(let right)):
                .files(left: left, right: right)
            case (.patch(let url, .old), .patch(let other, .new)) where url == other:
                .patch(url)
            default:
                nil
        }
    }

    /// What the window compares, for its title.
    package var windowTitle: String {
        switch (left.source, right.source) {
            case (nil, nil):
                "Git Diff Viewer"
            case (.gitRef(let repository, let leftRef), .directory(let folder))
            where repository.standardizedFileURL == folder.standardizedFileURL:
                "\(repository.lastPathComponent): \(GitCommit.abbreviated(leftRef)) ↔ working tree"
            case (.gitRef(let repository, let leftRef), .gitRef(let other, let rightRef)) where repository == other:
                "\(repository.lastPathComponent): \(GitCommit.abbreviated(leftRef)) ↔ \(GitCommit.abbreviated(rightRef))"
            case (.patch(let url, _), _), (_, .patch(let url, _)):
                url.lastPathComponent
            default:
                [left.source?.displayName, right.source?.displayName].compactMap { $0 }.joined(separator: " ↔ ")
        }
    }
}

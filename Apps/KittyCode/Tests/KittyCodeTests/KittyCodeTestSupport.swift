import AtelierText
import Foundation
import KittyCodecs
import KittyFileTree
import KittyGit
import KittyRenderer
import KittySyntax
import KittyTerminal
import KittyWidgets
import KittyWorkspace
import Testing

@testable import KittyEditor

struct TestGitProvider: FileStatusProvider, GitLineDecorationProvider {
    var statuses: [String: FileStatus] = [:]
    var decorations: [String: GitLineDecorations] = [:]
    var branchName: String? = nil
    var summary: FileStatusSummary = .init()

    func status(for path: String) -> FileStatus? {
        statuses[path]
    }

    func refresh() async {}

    func lineDecorations(for path: String, lines _: [String]) async -> GitLineDecorations {
        decorations[path] ?? .empty
    }
}

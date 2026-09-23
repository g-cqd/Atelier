import DiffGit

/// The working-tree paths one watcher debounce collected, sorted by what a reload of the folder could make of them
/// (GDV S2). A write to a listed file, or to a folder holding listed files, shows on reload. A new path shows unless
/// git ignores it, which only git can tell, dotfiles and hidden folders included. A path under a directory the
/// listing always skips, or a file whose kind it leaves out, never shows. Nothing under ``toolOutputDirectory``
/// reloads, listed or not: the tools the app starts write there, and a write of theirs must never reload (PERF-03).
package struct WorkingTreeWrites: Equatable, Sendable {
    /// SwiftPM's build directory, where sourcekit-lsp keeps its index (`.build/index-build`), at any depth, so a
    /// package inside a repository counts too.
    package static let toolOutputDirectory = ".build"

    /// Whether one of the writes hit a listed file or folder, which a reload shows without asking git.
    package let touchesListing: Bool
    /// The writes a reload would list unless git ignores them, sorted; empty once ``touchesListing`` settles it.
    package let unlisted: [String]

    /// - Parameters:
    ///   - paths: The written paths, relative to the folder.
    ///   - isListed: Whether a path names a listed file or a folder holding listed files.
    package init(_ paths: some Collection<String>, isListed: (String) -> Bool) {
        var unlisted: [String] = []
        for path in paths.sorted() where !Self.liesInToolOutput(path) {
            if isListed(path) {
                self.init(touchesListing: true, unlisted: [])
                return
            }
            if Self.mayBeListed(path) {
                unlisted.append(path)
            }
        }
        self.init(touchesListing: false, unlisted: unlisted)
    }

    private init(touchesListing: Bool, unlisted: [String]) {
        self.touchesListing = touchesListing
        self.unlisted = unlisted
    }

    private static func liesInToolOutput(_ path: String) -> Bool {
        path.split(separator: "/").contains { $0 == toolOutputDirectory }
    }

    /// Whether an unlisted `path` could appear in a later listing: not below a skipped directory, and not of a kind
    /// the listing leaves out.
    private static func mayBeListed(_ path: String) -> Bool {
        !path.split(separator: "/").contains { SourceLoader.skippedDirectories.contains(String($0)) }
            && SourceLoader.isSupported(path: path)
    }
}

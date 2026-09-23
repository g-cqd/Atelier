import DiffGit

/// The working-tree paths one watcher debounce collected, sorted by what a reload of the folder could make of them
/// (GDV S2). A write to a listed file, or to a folder holding listed files, shows on reload. A new path shows unless
/// git ignores it, which only git can tell. The rest never shows: a path under a directory the listing always skips,
/// a file whose kind the listing leaves out, and a new path in a hidden folder, where editors and build tools keep
/// their state (sourcekit-lsp's index under `.build` among them).
package struct WorkingTreeWrites: Equatable, Sendable {
    /// Whether one of the writes hit a listed file or folder, which a reload shows without asking git.
    package let touchesListing: Bool
    /// The writes a reload would list unless git ignores them, sorted; empty once ``touchesListing`` settles it.
    package let unlisted: [String]

    /// - Parameters:
    ///   - paths: The written paths, relative to the folder.
    ///   - isListed: Whether a path names a listed file or a folder holding listed files.
    package init(_ paths: some Collection<String>, isListed: (String) -> Bool) {
        var unlisted: [String] = []
        for path in paths.sorted() {
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

    /// Whether an unlisted `path` could appear in a later listing: not below a skipped directory, not of a kind the
    /// listing leaves out, and not in or at a hidden component.
    private static func mayBeListed(_ path: String) -> Bool {
        let components = path.split(separator: "/")
        let isExcluded = components.contains {
            $0.hasPrefix(".") || SourceLoader.skippedDirectories.contains(String($0))
        }
        return !isExcluded && SourceLoader.isSupported(path: path)
    }
}

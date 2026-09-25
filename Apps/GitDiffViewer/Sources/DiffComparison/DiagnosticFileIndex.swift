import DiffGit

/// Maps a render target's file order to the path each file's findings are keyed under: the new side's path, or
/// the comparison's own path for a file with no new side.
package enum DiagnosticFileIndex {
    package static func paths(for pairs: [FilePair]) -> [Int: String] {
        Dictionary(
            uniqueKeysWithValues: pairs.enumerated().map { index, pair in (index, pair.new?.relativePath ?? pair.path) }
        )
    }

    /// The same order mapped to the old side's path, which the left side's findings are keyed under; a file the old
    /// side lacks has no entry.
    package static func leftPaths(for pairs: [FilePair]) -> [Int: String] {
        Dictionary(
            uniqueKeysWithValues: pairs.enumerated()
                .compactMap { index, pair in
                    pair.old.map { (index, $0.relativePath) }
                })
    }
}

/// Both sides' maps of one render target, which ``DiffViewerModel/diagnosticFilePathMaps`` builds once per target.
package struct DiagnosticFilePaths: Equatable, Sendable {
    /// Each file index's right-side path; see ``DiagnosticFileIndex/paths(for:)``.
    package let right: [Int: String]
    /// Each file index's left-side path; see ``DiagnosticFileIndex/leftPaths(for:)``.
    package let left: [Int: String]

    package init(right: [Int: String], left: [Int: String]) {
        self.right = right
        self.left = left
    }

    package init(for pairs: [FilePair]) {
        self.init(right: DiagnosticFileIndex.paths(for: pairs), left: DiagnosticFileIndex.leftPaths(for: pairs))
    }
}

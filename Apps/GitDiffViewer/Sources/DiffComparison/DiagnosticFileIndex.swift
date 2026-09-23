import DiffGit

/// Maps a render target's file order to the path each file's findings are keyed under: the new side's path, or
/// the comparison's own path for a file with no new side.
package enum DiagnosticFileIndex {
    package static func paths(for pairs: [FilePair]) -> [Int: String] {
        Dictionary(
            uniqueKeysWithValues: pairs.enumerated().map { index, pair in (index, pair.new?.relativePath ?? pair.path) }
        )
    }
}

import DiffGit

/// Maps a render target's file order to the path each file's findings are keyed under. ``AtelierDiagnostics``
/// anchors every ``AtelierDiagnostics/Finding`` at the new (right) side's path, the one it actually reads to
/// analyze; falling back to the comparison's own (left) path covers a file with no new side, such as one deleted
/// on the right, which can never carry a finding but still needs an entry so a lookup by its row's `fileIndex`
/// does not crash.
package enum DiagnosticFileIndex {
    package static func paths(for pairs: [FilePair]) -> [Int: String] {
        Dictionary(
            uniqueKeysWithValues: pairs.enumerated().map { index, pair in (index, pair.new?.relativePath ?? pair.path) }
        )
    }
}

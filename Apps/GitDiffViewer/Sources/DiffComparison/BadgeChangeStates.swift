package import DiffGit

/// Where every path of one side, or of the unified explorer, stands against git's index: the files git reports with
/// a change the index does not hold yet, the folders above them, and one state for every other path.
package struct BadgeChangeStates: Sendable, Equatable {
    /// The state of every path that is neither a listed file nor a folder above one.
    private let fallback: BadgeChangeState
    /// Files with an unstaged or an untracked change; never a staged one, which ``fallback`` covers.
    private let files: [String: BadgeChangeState]
    /// Each folder above one of ``files``: unstaged when a file below it is, untracked when every one is untracked.
    private let folders: [String: BadgeChangeState]

    /// - Complexity: O(files × path depth)
    private init(files: [String: BadgeChangeState], fallback: BadgeChangeState) {
        var folders: [String: BadgeChangeState] = [:]
        for (path, state) in files {
            var folder = Substring(path)
            while let slash = folder.lastIndex(of: "/") {
                folder = folder[..<slash]
                let key = String(folder)
                // Every folder above holds at least what this one holds, so the walk can stop here.
                if let current = folders[key], Self.rank(current) >= Self.rank(state) { break }
                folders[key] = state
            }
        }
        self.fallback = fallback
        self.files = files
        self.folders = folders
    }

    /// One state for every path: the look of a side git reports nothing about.
    package static func uniform(_ state: BadgeChangeState) -> Self {
        Self(files: [:], fallback: state)
    }

    /// The states git's status gives a working tree, from entries named relative to the tree's root. A path the
    /// status leaves out is committed and unchanged, so staged.
    /// - Complexity: O(entries × path depth)
    package init(status entries: [GitStatusEntry]) {
        var files: [String: BadgeChangeState] = [:]
        for entry in entries {
            guard let state = Self.state(for: entry), state != .staged else { continue }
            files[entry.path] = state
        }
        self.init(files: files, fallback: .staged)
    }

    /// The state one status entry gives its path, read from the working-tree column: untracked for a path the index
    /// does not track, unstaged for any change the working tree holds over the index (so a change staged in part is
    /// unstaged, since the working tree shows the rest), staged when only the index moved; nil for an ignored path,
    /// which is no change at all.
    static func state(for entry: GitStatusEntry) -> BadgeChangeState? {
        switch entry.worktreeStatus {
            case .ignored: nil
            case .untracked: .untracked
            case .unmodified: .staged
            case .modified, .typeChanged, .added, .deleted, .renamed, .copied, .unmerged: .unstaged
        }
    }

    /// Both sides as one view keyed by left-side paths, the unified explorer's; see ``merged(_:with:ownPath:)``.
    /// - Complexity: O((left files + right files) × path depth)
    package static func merged(left: Self, right: Self, leftPath: (String) -> String) -> Self {
        merged(left, with: right, ownPath: leftPath)
    }

    /// Both sides as one side's explorer draws them, keyed by that side's paths: `own`'s files keep their paths, each
    /// of `other`'s moves to the path `ownPath` gives it, the more pressing state wins where both sides name a path,
    /// and the folders are aggregated again. A badge describes a change's git state in the comparison, not the side
    /// it is drawn on, so built once per explorer this draws each file in the same state in both (CARD-11).
    /// - Complexity: O((own files + other files) × path depth)
    package static func merged(_ own: Self, with other: Self, ownPath: (String) -> String) -> Self {
        var files = own.files
        for (path, state) in other.files {
            let key = ownPath(path)
            files[key] = files[key].map { morePressing($0, state) } ?? state
        }
        return Self(files: files, fallback: morePressing(own.fallback, other.fallback))
    }

    /// Where `path`, a file or a folder, stands against the index.
    package func state(of path: String) -> BadgeChangeState {
        files[path] ?? folders[path] ?? fallback
    }

    /// Staged, then untracked, then unstaged: a folder or a merged path takes the highest state among its sources.
    private static func rank(_ state: BadgeChangeState) -> Int {
        switch state {
            case .staged: 0
            case .untracked: 1
            case .unstaged: 2
        }
    }

    private static func morePressing(_ lhs: BadgeChangeState, _ rhs: BadgeChangeState) -> BadgeChangeState {
        rank(lhs) >= rank(rhs) ? lhs : rhs
    }
}

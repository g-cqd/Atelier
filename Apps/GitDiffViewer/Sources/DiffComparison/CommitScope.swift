package import DiffGit
package import Foundation

/// What a selection under the grouping by commit shows when it is a change of its own rather than the comparison's
/// (GIT-06 criterion 5, D39): a commit's files from its first parent to the commit, or the working tree's from `HEAD`.
/// The two sides are sources of their own, read at the blobs the listing recorded, and every file is a pair of the
/// change's own paths, so the render pipeline shows it as it shows any comparison.
package struct CommitScope: Sendable, Equatable {
    package enum Kind: Sendable, Equatable {
        case commit(CommitGrouping.Commit)
        /// The working tree's changes on top of the commit `HEAD` names.
        case uncommitted(head: String)
    }

    /// One file of the change, keyed in the list by its row.
    package struct File: Sendable, Equatable {
        /// The comparison's key for the file, which the list's row, and so the selection, names.
        package let rowPath: String
        /// The change's own sides: the path and blob before it, the path and blob after it. Its path is the one after
        /// the change, or the deleted one.
        package let pair: FilePair
        package let status: GitFileChange.Status

        /// The path the file had before this change, for a rename only.
        package var previousPath: String? {
            status == .renamed ? pair.old?.relativePath : nil
        }

        /// A rename that left the content as it was: only its path changed.
        package var isRenameWithoutChanges: Bool {
            status == .renamed && pair.old?.blobID != nil && pair.old?.blobID == pair.new?.blobID
        }

        /// How the file's badge and card read this change.
        package var summaryKind: FileChangeSummary.Kind {
            switch status {
                case .added: .added
                case .deleted: .deleted
                case .modified: .modified
                case .renamed: .renamed(to: pair.path)
            }
        }

        /// The status the explorer's badge letter would give this change.
        package var pathStatus: PathStatus { CommitScope.pathStatus(of: status) }
    }

    /// The selection this scope shows: a section's key, or the key of one file under it.
    package let key: String
    package let kind: Kind
    package let left: ComparisonSource
    package let right: ComparisonSource
    /// The files shown, in the list's order, each change's path once.
    package let files: [File]
    /// Whether the selection is one file under the section rather than the section itself.
    package let isSingleFile: Bool
    private let indexByPath: [String: Int]

    private init(
        key: String, kind: Kind, left: ComparisonSource, right: ComparisonSource, files: [File], isSingleFile: Bool
    ) {
        var seen: Set<String> = []
        // A rename the net diff split into a deletion and an addition lists one change under two rows.
        let unique = files.filter { seen.insert($0.pair.path).inserted }
        self.key = key
        self.kind = kind
        self.left = left
        self.right = right
        self.files = unique
        self.isSingleFile = isSingleFile
        indexByPath = Dictionary(
            unique.enumerated().map { ($1.pair.path, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// A commit's own change to `rows`: its first parent on the left, the commit on the right, both read from the
    /// repository by the blob ids the listing recorded.
    package init(
        key: String, commit: CommitGrouping.Commit, repository: URL, rows: [CommitGrouping.Row], isSingleFile: Bool
    ) {
        // A root commit has no parent: every file of it is an addition, so its left side is never read.
        let parent = commit.parentIDs.first ?? commit.id
        let files = rows.compactMap { row in
            row.change.map { change in
                File(rowPath: row.path, pair: Self.pair(for: change) { Self.committed(change) }, status: change.status)
            }
        }
        self.init(
            key: key, kind: .commit(commit), left: .gitRef(repository: repository, ref: parent),
            right: .gitRef(repository: repository, ref: commit.id), files: files, isSingleFile: isSingleFile)
    }

    /// The working tree's own change to `rows`: `head` on the left, the working tree on the right. A working-tree
    /// file's blob is the one its side's listing hashed, which `diff --raw` leaves out.
    package init(
        key: String, head: String, repository: URL, workingTree: ComparisonSource, rows: [CommitGrouping.Row],
        isSingleFile: Bool, workingTreeEntry: (String) -> SourceEntry?
    ) {
        let files = rows.compactMap { row in
            row.change.map { change in
                File(
                    rowPath: row.path,
                    pair: Self.pair(for: change) {
                        workingTreeEntry(change.path)
                            ?? SourceEntry(relativePath: change.path, blobID: change.newBlobID, size: 0)
                    },
                    status: change.status)
            }
        }
        self.init(
            key: key, kind: .uncommitted(head: head), left: .gitRef(repository: repository, ref: head),
            right: workingTree, files: files, isSingleFile: isSingleFile)
    }

    /// The file the scope shows under `path`, the change's own path.
    package func file(atPath path: String) -> File? {
        indexByPath[path].map { files[$0] }
    }

    /// The status the explorer's badge letter gives a change of this kind.
    package static func pathStatus(of status: GitFileChange.Status) -> PathStatus {
        switch status {
            case .added: .onlyRight
            case .deleted: .onlyLeft
            case .modified: .different
            case .renamed: .renamed
        }
    }

    /// The change's two sides: nothing on the left for an addition, nothing on the right for a deletion.
    private static func pair(for change: GitFileChange, new: () -> SourceEntry?) -> FilePair {
        let old =
            change.status == .added
            ? nil : SourceEntry(relativePath: change.oldPath ?? change.path, blobID: change.oldBlobID, size: 0)
        return FilePair(path: change.path, old: old, new: change.status == .deleted ? nil : new())
    }

    private static func committed(_ change: GitFileChange) -> SourceEntry {
        SourceEntry(relativePath: change.path, blobID: change.newBlobID, size: 0)
    }
}

public import Foundation

/// One commit of a history listing: who made it, when, why, and the files it changed against its first parent.
public struct GitCommitChanges: Sendable, Hashable, Identifiable {
    /// The full commit id.
    public let id: String
    /// Full ids of the parents, the first parent first; empty for a root commit.
    public let parentIDs: [String]
    public let authorName: String
    public let authorDate: Date
    /// The message's first paragraph on one line, as git's `%s` folds it.
    public let subject: String
    /// The files the commit changed, in git's order. A merge listed along first parents holds everything it brought
    /// in; a merge listed without them holds nothing.
    public let changes: [GitFileChange]

    public init(
        id: String, parentIDs: [String], authorName: String, authorDate: Date, subject: String,
        changes: [GitFileChange]
    ) {
        self.id = id
        self.parentIDs = parentIDs
        self.authorName = authorName
        self.authorDate = authorDate
        self.subject = subject
        self.changes = changes
    }

    public var isMerge: Bool { parentIDs.count > 1 }
}

/// One file a commit, or the working tree, changed: a record of `git diff --raw`.
public struct GitFileChange: Sendable, Hashable {
    public enum Status: Sendable, Hashable {
        /// Added; a copy reads as added too, since its source did not change.
        case added
        /// Changed in place; a change of type (a file becoming a link) or an unmerged path reads as modified.
        case modified
        case deleted
        /// Moved from ``GitFileChange/oldPath``, its content possibly changed as well.
        case renamed
    }

    public let status: Status
    /// The path after the change, or the deleted path for a deletion.
    public let path: String
    /// The path before a rename; nil for every other status.
    public let oldPath: String?
    /// The blob before the change; nil for an addition.
    public let oldBlobID: String?
    /// The blob after the change; nil for a deletion, and for a working-tree file git has not hashed.
    public let newBlobID: String?

    public init(
        status: Status, path: String, oldPath: String? = nil, oldBlobID: String? = nil, newBlobID: String? = nil
    ) {
        self.status = status
        self.path = path
        self.oldPath = oldPath
        self.oldBlobID = oldBlobID
        self.newBlobID = newBlobID
    }
}

/// A page of a history listing, newest commit first, and where the next page's walk starts.
public struct GitCommitPage: Sendable, Hashable {
    public let commits: [GitCommitChanges]
    /// True when the listing reached the start of the range: fewer commits than asked for came back, or the oldest
    /// has no parent.
    public let isComplete: Bool
    /// The tip of the next page, the first parent of the oldest commit listed, when the listing followed first
    /// parents and the range goes on: the next page lists `from..continuation`, so git starts its walk where this
    /// one stopped instead of walking the listed commits again, as `--skip` would. Nil when the range ended, and for
    /// a listing of every parent, whose walk has no single place to go on from.
    public let continuation: String?

    public init(commits: [GitCommitChanges], isComplete: Bool, continuation: String?) {
        self.commits = commits
        self.isComplete = isComplete
        self.continuation = continuation
    }
}

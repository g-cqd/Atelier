public import Foundation

/// A blob of a tree, identified by its path relative to the repository root.
public struct GitTreeEntry: Sendable, Hashable {
    public let relativePath: String
    /// Git blob object id; nil when the file was too large to hash.
    public let blobID: String?
    public let size: Int

    public init(relativePath: String, blobID: String?, size: Int) {
        self.relativePath = relativePath
        self.blobID = blobID
        self.size = size
    }
}

public struct GitCommit: Sendable, Hashable, Identifiable {
    public let hash: String
    public let shortHash: String
    public let subject: String

    public init(hash: String, shortHash: String, subject: String) {
        self.hash = hash
        self.shortHash = shortHash
        self.subject = subject
    }

    public var id: String { hash }
}

public struct RepositoryInfo: Sendable, Hashable {
    public let root: URL
    public let branches: [String]
    public let tags: [String]
    public let commits: [GitCommit]

    public init(root: URL, branches: [String], tags: [String], commits: [GitCommit]) {
        self.root = root
        self.branches = branches
        self.tags = tags
        self.commits = commits
    }
}

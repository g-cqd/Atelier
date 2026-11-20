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

/// One entry of `git remote -v`, the `(fetch)` URL only.
public struct GitRemote: Sendable, Equatable {
    public let name: String
    public let fetchURL: String

    public init(name: String, fetchURL: String) {
        self.name = name
        self.fetchURL = fetchURL
    }
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

/// One entry of the index, as `git ls-files -s` lists it: the blob git stores for a tracked path.
public struct GitIndexEntry: Sendable, Hashable {
    /// The path, relative to the directory git ran in.
    public let path: String
    /// The octal mode: `100644`, `100755`, `120000` for a symbolic link, `160000` for a submodule.
    public let mode: String
    public let objectID: String
    /// 0 for a merged path, 1 to 3 for the sides of a conflict.
    public let stage: Int

    public init(path: String, mode: String, objectID: String, stage: Int) {
        self.path = path
        self.mode = mode
        self.objectID = objectID
        self.stage = stage
    }

    /// Whether the entry is a submodule's recorded commit rather than a file.
    public var isSubmodule: Bool { mode == "160000" }
}

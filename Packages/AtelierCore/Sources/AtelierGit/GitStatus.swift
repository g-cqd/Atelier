/// What git says about one path relative to the index and the working tree; the vocabulary both apps badge with.
public enum FileStatus: String, Sendable, Hashable, CaseIterable {
    case modified
    case added
    case untracked
    case deleted
    case renamed
    case conflicted
    case ignored
    case clean

    /// The one-letter badge, empty for a clean path.
    public var indicator: String {
        switch self {
            case .modified: "M"
            case .added: "A"
            case .untracked: "?"
            case .deleted: "D"
            case .renamed: "R"
            case .conflicted: "!"
            case .ignored: "I"
            case .clean: ""
        }
    }

    /// How much a status matters when a directory takes the status of its children: a conflict outranks a
    /// deletion, which outranks a modification, and so on down to clean.
    public var severity: Int {
        switch self {
            case .conflicted: 5
            case .deleted: 4
            case .modified, .renamed: 3
            case .added: 2
            case .untracked: 1
            case .ignored, .clean: 0
        }
    }
}

/// How many paths carry each status that counts as a change.
public struct FileStatusSummary: Sendable, Equatable {
    public var modified: Int
    public var added: Int
    public var untracked: Int
    public var deleted: Int
    public var conflicted: Int

    public init(modified: Int = 0, added: Int = 0, untracked: Int = 0, deleted: Int = 0, conflicted: Int = 0) {
        self.modified = modified
        self.added = added
        self.untracked = untracked
        self.deleted = deleted
        self.conflicted = conflicted
    }

    public var isEmpty: Bool {
        modified == 0 && added == 0 && untracked == 0 && deleted == 0 && conflicted == 0
    }

    /// Counts `status` once; a rename counts as a modification, ignored and clean paths do not count.
    public mutating func count(_ status: FileStatus) {
        switch status {
            case .modified, .renamed: modified += 1
            case .added: added += 1
            case .untracked: untracked += 1
            case .deleted: deleted += 1
            case .conflicted: conflicted += 1
            case .ignored, .clean: break
        }
    }
}

/// One path git reports, relative to the repository root.
public struct GitStatusEntry: Sendable, Hashable {
    public let path: String
    /// Where a renamed or copied path came from.
    public let originalPath: String?
    public let status: FileStatus
    public let isSubmodule: Bool

    public init(path: String, originalPath: String? = nil, status: FileStatus, isSubmodule: Bool = false) {
        self.path = path
        self.originalPath = originalPath
        self.status = status
        self.isSubmodule = isSubmodule
    }
}

/// The `# branch.*` headers of a status: nil `head` for a detached head, nil `upstream` when none is set.
public struct GitBranchStatus: Sendable, Hashable {
    public let head: String?
    public let upstream: String?
    public let ahead: Int
    public let behind: Int

    public init(head: String?, upstream: String? = nil, ahead: Int = 0, behind: Int = 0) {
        self.head = head
        self.upstream = upstream
        self.ahead = ahead
        self.behind = behind
    }
}

/// One `git status` reading: the branch headers and every path that is not clean.
public struct GitStatusSnapshot: Sendable, Equatable {
    public let branch: GitBranchStatus?
    public let entries: [GitStatusEntry]

    public init(branch: GitBranchStatus?, entries: [GitStatusEntry]) {
        self.branch = branch
        self.entries = entries
    }

    /// The counts of every entry that is a change.
    public var summary: FileStatusSummary {
        var summary = FileStatusSummary()
        for entry in entries {
            summary.count(entry.status)
        }
        return summary
    }

    /// The status of every reported path and, when asked, of each directory above it: a directory takes the most
    /// severe status among its files. The repository root itself gets no entry.
    /// - Complexity: O(entries × path depth)
    public func statusesByPath(includingDirectories: Bool) -> [String: FileStatus] {
        var statuses: [String: FileStatus] = [:]
        for entry in entries {
            statuses[entry.path] = entry.status
            guard includingDirectories else { continue }
            var directory = entry.path
            while let slash = directory.lastIndex(of: "/") {
                directory = String(directory[..<slash])
                if let current = statuses[directory], current.severity >= entry.status.severity { break }
                statuses[directory] = entry.status
            }
        }
        return statuses
    }
}

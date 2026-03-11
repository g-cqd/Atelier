public enum FileStatus: String, Sendable, Equatable, Hashable {
    case modified
    case added
    case untracked
    case deleted
    case renamed
    case conflicted
    case ignored
    case clean

    public var indicator: String {
        switch self {
        case .modified: return "M"
        case .added: return "A"
        case .untracked: return "?"
        case .deleted: return "D"
        case .renamed: return "R"
        case .conflicted: return "!"
        case .ignored: return "I"
        case .clean: return ""
        }
    }
}

public enum FileStatusColor: Sendable {
    case modified
    case added
    case untracked
    case deleted
    case conflicted
    case clean
}

extension FileStatus {
    public var statusColor: FileStatusColor {
        switch self {
        case .modified, .renamed: return .modified
        case .added: return .added
        case .untracked: return .untracked
        case .deleted: return .deleted
        case .conflicted: return .conflicted
        case .ignored, .clean: return .clean
        }
    }
}

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
}

public protocol FileStatusProvider: Sendable {
    func status(for path: String) -> FileStatus?
    var branchName: String? { get }
    var summary: FileStatusSummary { get }
    func refresh() async
}

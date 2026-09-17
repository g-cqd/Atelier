public import AtelierGit

/// The status vocabulary is the core's; the editor adds the colour it paints each status in.
public typealias FileStatus = AtelierGit.FileStatus
public typealias FileStatusSummary = AtelierGit.FileStatusSummary

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

public protocol FileStatusProvider: Sendable {
    func status(for path: String) -> FileStatus?
    var branchName: String? { get }
    var summary: FileStatusSummary { get }
    func refresh() async
}

import AtelierDiff
import AtelierGit
import AtelierSyntaxModel
public import Foundation

/// One side of a comparison.
public enum ComparisonSource: Hashable, Sendable {
    case file(URL)
    case directory(URL)
    /// A branch, tag or commit of a repository, rooted at the repository root.
    case gitRef(repository: URL, ref: String)
    /// One side of a unified diff or git patch file.
    case patch(URL, side: PatchSide)

    public enum PatchSide: Hashable, Sendable {
        case old, new
    }

    public var displayName: String {
        switch self {
            case .file(let url), .directory(let url):
                url.lastPathComponent
            case .gitRef(let repository, let ref):
                "\(repository.lastPathComponent) @ \(ref)"
            case .patch(let url, let side):
                "\(url.lastPathComponent) (\(side == .old ? "before" : "after"))"
        }
    }

    public var detail: String {
        switch self {
            case .file(let url), .directory(let url), .patch(let url, _):
                url.path(percentEncoded: false)
            case .gitRef(let repository, let ref):
                "\(ref) in \(repository.path(percentEncoded: false))"
        }
    }

    public var isSingleFile: Bool {
        if case .file = self { return true }
        return false
    }
}

/// How a path on one side relates to the same path on the other side.
public enum PathStatus: Sendable {
    case same
    case different
    case onlyLeft
    case onlyRight
    /// Present on both sides under different paths.
    case renamed
}

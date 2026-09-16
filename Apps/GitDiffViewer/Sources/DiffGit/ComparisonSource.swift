import DiffCore
package import Foundation

/// One side of a comparison.
package enum ComparisonSource: Hashable, Sendable {
    case file(URL)
    case directory(URL)
    /// A branch, tag or commit of a repository, rooted at the repository root.
    case gitRef(repository: URL, ref: String)
    /// One side of a unified diff or git patch file.
    case patch(URL, side: PatchSide)

    package enum PatchSide: Hashable, Sendable {
        case old, new
    }

    package var displayName: String {
        switch self {
            case .file(let url), .directory(let url):
                url.lastPathComponent
            case .gitRef(let repository, let ref):
                "\(repository.lastPathComponent) @ \(ref)"
            case .patch(let url, let side):
                "\(url.lastPathComponent) (\(side == .old ? "before" : "after"))"
        }
    }

    package var detail: String {
        switch self {
            case .file(let url), .directory(let url), .patch(let url, _):
                url.path(percentEncoded: false)
            case .gitRef(let repository, let ref):
                "\(ref) in \(repository.path(percentEncoded: false))"
        }
    }

    package var isSingleFile: Bool {
        if case .file = self { return true }
        return false
    }
}

/// How a path on one side relates to the same path on the other side.
package enum PathStatus: Sendable {
    case same
    case different
    case onlyLeft
    case onlyRight
    /// Present on both sides under different paths.
    case renamed
}

/// A file inside a source, identified by its path relative to the source root.
package struct SourceEntry: Sendable, Hashable {
    package let relativePath: String
    /// Git blob object id; nil when the file was too large to hash.
    package let blobID: String?
    package let size: Int
}

package struct GitCommit: Sendable, Hashable, Identifiable {
    package let hash: String
    package let shortHash: String
    package let subject: String

    package var id: String { hash }
}

package struct RepositoryInfo: Sendable, Hashable {
    package let root: URL
    package let branches: [String]
    package let tags: [String]
    package let commits: [GitCommit]
}

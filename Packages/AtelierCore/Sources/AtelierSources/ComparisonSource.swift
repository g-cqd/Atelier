import AtelierDiff
public import AtelierGit
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

    /// Backed by ``descriptor(repository:)`` (with no repository, so a directory is never mistaken for a working
    /// tree) so this and the descriptor's fields cannot drift apart.
    public var displayName: String {
        let described = descriptor(repository: nil)
        switch self {
            case .file, .directory:
                return described.primary
            case .gitRef:
                return "\(described.context) @ \(described.primary)"
            case .patch:
                return "\(described.context) (\(described.primary))"
        }
    }

    /// Backed by ``descriptor(repository:)``, for the same reason ``displayName`` is.
    public var detail: String {
        descriptor(repository: nil).detail
    }

    public var isSingleFile: Bool {
        if case .file = self { return true }
        return false
    }

    /// Describes this source uniformly for display: what family it belongs to, the secondary text (repository or
    /// parent folder), the primary text (ref, "Working Tree", file name, or patch side), and a tooltip.
    ///
    /// `repository`, when it is the one this source was resolved against, lets a `.directory` at that repository's
    /// root be recognized as the working tree rather than as an ordinary folder -- without it, the working-tree
    /// side of a repository comparison read as a folder named after the repository itself, out of step with its
    /// ref-carrying sibling, which named the same repository as its context and a ref as its primary text.
    public func descriptor(repository: RepositoryInfo?) -> SourceDescriptor {
        switch self {
            case .gitRef(let repositoryURL, let ref):
                SourceDescriptor(
                    symbol: .branch, context: repositoryURL.lastPathComponent, primary: GitCommit.abbreviated(ref),
                    detail: "\(ref) in \(repositoryURL.path(percentEncoded: false))")
            case .directory(let url) where url.standardizedFileURL == repository?.root.standardizedFileURL:
                SourceDescriptor(
                    symbol: .workingTree, context: url.lastPathComponent, primary: "Working Tree",
                    detail: url.path(percentEncoded: false))
            case .directory(let url):
                SourceDescriptor(
                    symbol: .folder, context: url.deletingLastPathComponent().lastPathComponent,
                    primary: url.lastPathComponent, detail: url.path(percentEncoded: false))
            case .file(let url):
                SourceDescriptor(
                    symbol: .file, context: url.deletingLastPathComponent().lastPathComponent,
                    primary: url.lastPathComponent, detail: url.path(percentEncoded: false))
            case .patch(let url, let side):
                SourceDescriptor(
                    symbol: .patch, context: url.lastPathComponent, primary: side == .old ? "before" : "after",
                    detail: url.path(percentEncoded: false))
        }
    }
}

/// A source described uniformly regardless of what it names, so every place that shows one -- a toolbar control,
/// a window title, a status line -- draws from the same rules instead of each switching over ``ComparisonSource``
/// on its own.
public struct SourceDescriptor: Sendable, Equatable {
    /// What family of source this is, for the app to map to an icon of its choosing.
    public enum Symbol: String, Sendable {
        case branch
        case folder
        case file
        case patch
        case workingTree
    }

    public let symbol: Symbol
    /// Secondary text: the repository's name, the parent folder's name, or the patch file's name.
    public let context: String
    /// Primary text: the ref, "Working Tree", the file name, or the patch side.
    public let primary: String
    /// The tooltip: the full path, or the ref and the path it lives in.
    public let detail: String
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

import DiffCore
import DiffGit
import Foundation

/// Whether what the detail area shows is the comparison the window asks for, for the marker that keeps a previous one
/// from reading as current (book D13).
extension DiffViewerModel {
    /// How what the detail area shows relates to what the window now asks for. After Swap, another ref or another
    /// folder, the previous comparison stays on screen until the new one replaces it in one step, and this says it
    /// is the previous one; a load or a render that fails leaves it there with the failure. A reload of the same
    /// sources marks nothing: what is shown is still their comparison while it refreshes. A commit group's own change
    /// is rendered from sides of its own, which are then the ones asked for (D39).
    package var shownComparison: ShownComparison {
        guard let shown = pipeline.publishedSources else { return .current }
        if let failure = loadFailure ?? renderError { return .previousAfterFailure(failure) }
        let askedLeft = commitScope?.left ?? left.source
        let askedRight = commitScope?.right ?? right.source
        if isSwitching || showsPreviousSelection || shown.left != askedLeft || shown.right != askedRight {
            return .previous
        }
        return .current
    }

    /// Why the comparison meant to replace what is shown could not load: a repository that could not be opened, or a
    /// side whose files could not be listed; nil otherwise.
    package var loadFailure: String? {
        if let switchFailure { return switchFailure }
        if failedLoads.contains(.left), let message = left.errorMessage { return message }
        if failedLoads.contains(.right), let message = right.errorMessage { return message }
        return nil
    }

    /// A side's listing landed: remembers whether it failed, which holds the comparison where it is, then
    /// recomputes it.
    func entriesChanged(on side: Side) {
        let state = side == .left ? left : right
        if state.errorMessage == nil {
            failedLoads.remove(side)
        } else {
            failedLoads.insert(side)
        }
        sourcesChanged()
    }

    /// Whether comparing `leftRef` with `rightRef`, or with the working tree, in the repository at `url` is what the
    /// sides already compare, as when HEAD moved; only another comparison is marked while it loads.
    func alreadyCompares(_ url: URL, leftRef: String, rightRef: String?) -> Bool {
        let path = Self.displayPath(of: url)
        guard case .gitRef(let repository, let ref) = left.source, ref == leftRef,
            Self.displayPath(of: repository) == path
        else { return false }
        switch (right.source, rightRef) {
            case (.directory(let folder), nil):
                return Self.displayPath(of: folder) == path
            case (.gitRef(let other, let otherRef), let wanted?):
                return otherRef == wanted && Self.displayPath(of: other) == path
            default:
                return false
        }
    }

    /// `url`'s standardized path without the trailing slash a folder URL carries, so two spellings of one folder
    /// compare equal.
    static func displayPath(of url: URL) -> String {
        let path = url.standardizedFileURL.path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}

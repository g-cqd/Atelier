import Foundation

/// Path validation and canonicalization utilities.
///
/// All checks resolve symlinks before comparison so that crafted symlink
/// chains cannot escape a designated root directory.
public enum SecurePath {
    /// Reasons a path can fail validation.
    public enum ValidationError: Error, Sendable, Equatable {
        /// The resolved path lies outside the resolved root.
        case outsideRoot
        /// The path string is structurally invalid (reserved for future use).
        case invalidPath
    }

    /// Validates that `path` resolves to a location inside `root`.
    ///
    /// - Parameters:
    ///   - path: The candidate path to validate.
    ///   - root: The directory that must contain `path`.
    /// - Throws: ``ValidationError/outsideRoot`` when the resolved `path` does
    ///   not start with the resolved `root`.
    public static func validate(_ path: String, root: String) throws(ValidationError) {
        guard isValid(path, root: root) else {
            throw .outsideRoot
        }
    }

    /// Returns `true` when `path` resolves to a location inside `root`.
    ///
    /// - Parameters:
    ///   - path: The candidate path.
    ///   - root: The directory that must contain `path`.
    public static func isValid(_ path: String, root: String) -> Bool {
        let resolved = (path as NSString).resolvingSymlinksInPath
        let resolvedRoot = (root as NSString).resolvingSymlinksInPath
        return resolved == resolvedRoot || resolved.hasPrefix(resolvedRoot + "/")
    }
}

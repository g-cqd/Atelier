import Foundation

/// Path-string helpers shared by the editor library and the executable.
public enum PathUtilities {
    /// Expands a leading `~` or `~/` to the home directory; any other path, `~user` included, comes back unchanged.
    public static func expandingTilde(in path: String) -> String {
        guard path.hasPrefix("~") else { return path }
        if path == "~" { return NSHomeDirectory() }
        if path.hasPrefix("~/") {
            return NSHomeDirectory() + String(path.dropFirst())
        }
        return path
    }
}

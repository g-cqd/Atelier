import Foundation

/// Path-string helpers shared between `KittyEditor` and the executable
/// shell. Public so the `KittyCode` executable can call into it without
/// going through `@testable import`.
public enum PathUtilities {
    /// Expands a leading `~` or `~/` to the current user's home directory.
    /// Equivalent to `(path as NSString).expandingTildeInPath` for the
    /// shapes kittycode actually accepts (no `~username`); avoids the
    /// Foundation bridge.
    public static func expandingTilde(in path: String) -> String {
        guard path.hasPrefix("~") else { return path }
        if path == "~" { return NSHomeDirectory() }
        if path.hasPrefix("~/") {
            return NSHomeDirectory() + String(path.dropFirst())
        }
        return path
    }
}

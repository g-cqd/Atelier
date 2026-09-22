import CryptoKit
package import Foundation

/// Identifies a project — a git repository root — for the per-project settings overlay (`ViewerSettings.adoptProject`).
/// Two identities are equal exactly when they were built from the same resolved root path, so reopening the same
/// repository through a different launch path (command line, recents, a subfolder that resolves to the same root)
/// still lands on the same overlay.
package struct ProjectIdentity: Sendable, Hashable {
    /// A short, stable fingerprint of the resolved root path, safe to embed in a defaults key.
    package let key: String
    /// The root path, kept only for display in the settings review affordance; never used as a lookup key.
    package let displayPath: String

    /// - Parameter root: The repository's resolved root directory (not a subfolder — callers resolve that first,
    ///   typically through `GitClient.repositoryRoot(containing:runner:)`).
    package init(root: URL) {
        let path = root.standardizedFileURL.path
        displayPath = path
        key = Self.fingerprint(of: path)
    }

    /// SHA-256 of the standardized path, truncated to 16 hex characters (64 bits) — plenty to keep the handful of
    /// repositories one person works in from colliding, short enough to stay readable in a defaults key or a
    /// registry entry.
    private static func fingerprint(of path: String) -> String {
        let digest = SHA256.hash(data: Data(path.utf8))
        var characters: [UInt8] = []
        characters.reserveCapacity(16)
        for byte in digest.prefix(8) {
            characters.append(hexDigits[Int(byte >> 4)])
            characters.append(hexDigits[Int(byte & 0x0F)])
        }
        return String(decoding: characters, as: UTF8.self)
    }

    private static let hexDigits: [UInt8] = Array("0123456789abcdef".utf8)
}

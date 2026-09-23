import CryptoKit
package import Foundation

/// Identifies a project, a git repository root, for the per-project settings overlay. Two identities are equal
/// exactly when built from the same resolved root path, however the repository was opened.
package struct ProjectIdentity: Sendable, Hashable {
    /// A short, stable fingerprint of the resolved root path, safe to embed in a defaults key.
    package let key: String
    /// The root path, for display only; never used as a lookup key.
    package let displayPath: String

    /// The root folder's name, which is how a list names the project.
    package var name: String { (displayPath as NSString).lastPathComponent }

    /// - Parameter root: The repository's resolved root directory, not a subfolder.
    package init(root: URL) {
        let path = root.standardizedFileURL.path
        displayPath = path
        key = Self.fingerprint(of: path)
    }

    /// SHA-256 of the standardized path, truncated to 16 hex characters (64 bits) to stay short in a defaults key.
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

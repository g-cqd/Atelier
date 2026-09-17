import Foundation

/// A node in a file system tree.
///
/// Represents either a regular file or a directory with optional children.
/// Children are populated lazily by ``DirectoryScanner`` when a directory
/// is first expanded via ``FileTreeNavigator/toggleExpand(in:at:)``.
public struct FileNode: Sendable {
    public let name: String
    public let path: String
    public let isDirectory: Bool
    public var children: [FileNode]
    public var isExpanded: Bool

    public init(
        name: String,
        path: String,
        isDirectory: Bool,
        children: [FileNode] = [],
        isExpanded: Bool = false
    ) {
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.children = children
        self.isExpanded = isExpanded
    }

    /// A three-character prefix icon suitable for terminal display.
    public var icon: String {
        if isDirectory {
            return isExpanded ? "[-]" : "[+]"
        }
        return "   "
    }
}

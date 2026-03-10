import Foundation

struct FileEntry: Sendable {
    let name: String
    let path: String
    let isDirectory: Bool
    var children: [FileEntry]
    var isExpanded: Bool

    var icon: String {
        if isDirectory {
            return isExpanded ? "[-]" : "[+]"
        }
        return "   "
    }
}
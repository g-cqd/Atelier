import Darwin
import Foundation

/// Makes a path a tool reported relative to the analysis root, whichever spelling of the root the tool used.
///
/// One directory has several spellings: the path as the caller gave it, possibly through a symlink; its physical
/// path, as `realpath(3)` and `getcwd` give it, `/private` included (`/private/var/…`); and Foundation's resolution,
/// which resolves symlinks but strips `/private` (`/var/…`), as the Swift analyzers print it. A reported path lies
/// under the root only when a spelling is followed by `/`: a root of `/repo` never claims `/repo-other/A.swift`.
struct RootRelativePath: Sendable {
    /// Each distinct spelling of the root, ending in `/`, longest first.
    private let prefixes: [String]

    /// Resolves the spellings of `root` against the file system once; a root that does not exist keeps the
    /// spellings that need no lookup.
    init(root: URL) {
        let spellings: [String?] = [
            root.path, root.standardizedFileURL.path, Self.physicalPath(of: root.path),
            root.resolvingSymlinksInPath().path
        ]
        var seen: Set<String> = []
        prefixes =
            spellings.compactMap { spelling -> String? in
                guard let spelling, !spelling.isEmpty else { return nil }
                return spelling.hasSuffix("/") ? spelling : spelling + "/"
            }
            .filter { seen.insert($0).inserted }
            .sorted { $0.count > $1.count }
    }

    /// `reported` relative to the root, `/`-separated. `reported` is a `file:` URI, whose path is percent-decoded, a
    /// plain absolute path, taken as written, or a reference already relative to the root, returned without its
    /// leading `./`. An absolute path outside the root, or naming the root itself, is returned whole.
    /// - Complexity: O(*n*) in the length of `reported`, per spelling of the root.
    func relativePath(of reported: String) -> String {
        guard let absolute = Self.absolutePath(of: reported) else {
            var relative = Substring(reported)
            while relative.hasPrefix("./") { relative = relative.dropFirst(2) }
            return String(relative)
        }
        guard let prefix = prefixes.first(where: absolute.hasPrefix) else { return absolute }
        let relative = absolute.dropFirst(prefix.count)
        return relative.isEmpty ? absolute : String(relative)
    }

    /// The absolute path `reported` names, or nil for a relative reference.
    private static func absolutePath(of reported: String) -> String? {
        if reported.hasPrefix("/") { return reported }
        guard reported.prefix(5).lowercased() == "file:" else { return nil }
        if let url = URL(string: reported), url.isFileURL { return url.path }
        // A URI Foundation cannot parse keeps the path its `file://` prefix spells out, if any.
        let path = reported.dropFirst("file://".count)
        return path.hasPrefix("/") ? String(path) : nil
    }

    /// `path` with every symlink resolved and `/private` kept, as `realpath(3)` returns it; nil when it does not
    /// exist.
    private static func physicalPath(of path: String) -> String? {
        // Given no buffer, realpath(3) allocates the result; it is copied into a String before it is freed.
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}

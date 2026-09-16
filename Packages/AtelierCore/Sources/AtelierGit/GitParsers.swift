public import Foundation

/// Pure parsers for git's plumbing output: bytes in, values out, no process. Each one takes the exact format the
/// matching ``GitClient`` command asks git for.
public enum GitParsers {
    /// Splits `ls-tree -r -l -z` output: `<mode> blob <id> <size>\t<path>\0` per file; trees and unsupported
    /// paths are left out.
    public static func tree(_ data: Data, isSupported: (String) -> Bool) -> [GitTreeEntry] {
        var entries: [GitTreeEntry] = []
        for record in data.split(separator: 0) {
            guard let tab = record.firstIndex(of: 9) else { continue }
            let header = String(decoding: record[record.startIndex ..< tab], as: UTF8.self)
            let path = String(decoding: record[record.index(after: tab)...], as: UTF8.self)
            guard isSupported(path) else { continue }
            let fields = header.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count == 4, fields[1] == "blob" else { continue }
            entries.append(GitTreeEntry(relativePath: path, blobID: String(fields[2]), size: Int(fields[3]) ?? 0))
        }
        return entries
    }

    /// Splits `ls-files -z` output: one NUL-terminated path per record, in index order.
    public static func paths(_ data: Data) -> [String] {
        data.split(separator: 0, omittingEmptySubsequences: true).map { String(decoding: $0, as: UTF8.self) }
    }

    /// Splits `cat-file --batch` output: `<id> blob <size>\n<bytes>\n` per object, `<id> missing\n` otherwise.
    public static func batch(_ output: Data) -> [String: Data] {
        var blobs: [String: Data] = [:]
        var cursor = output.startIndex
        while cursor < output.endIndex, let newline = output[cursor...].firstIndex(of: 10) {
            let fields = String(decoding: output[cursor ..< newline], as: UTF8.self).split(separator: " ")
            cursor = output.index(after: newline)
            guard fields.count == 3, let size = Int(fields[2]) else { continue }
            let end = min(cursor + size, output.endIndex)
            blobs[String(fields[0])] = output.subdata(in: cursor ..< end)
            cursor = min(end + 1, output.endIndex)
        }
        return blobs
    }

    /// Splits `diff --name-status -z` output: `R<score>\0<old>\0<new>\0` per rename.
    public static func renames(_ data: Data) -> [String: String] {
        var renames: [String: String] = [:]
        let fields = data.split(separator: 0, omittingEmptySubsequences: true)
            .map { String(decoding: $0, as: UTF8.self) }
        var index = 0
        while index + 2 < fields.count {
            if fields[index].hasPrefix("R") { renames[fields[index + 1]] = fields[index + 2] }
            index += 3
        }
        return renames
    }

    /// One short ref name per line; a remote's `HEAD` pointer is left out because it duplicates a branch.
    public static func references(_ data: Data) -> [String] {
        String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init).filter { !$0.hasSuffix("/HEAD") }
    }

    /// One `<hash>\u{1f}<short hash>\u{1f}<subject>` line per commit; the unit separator keeps subjects with
    /// spaces intact.
    public static func commits(_ data: Data) -> [GitCommit] {
        String(decoding: data, as: UTF8.self).split(separator: "\n")
            .compactMap { line in
                let fields = line.split(separator: "\u{1f}", maxSplits: 2, omittingEmptySubsequences: false)
                guard fields.count == 3 else { return nil }
                return GitCommit(hash: String(fields[0]), shortHash: String(fields[1]), subject: String(fields[2]))
            }
    }
}

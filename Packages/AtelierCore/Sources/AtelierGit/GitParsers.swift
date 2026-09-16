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

    /// Splits `status --porcelain=v2 -z --branch` output: NUL-terminated records, a rename or copy record followed by
    /// its original path as one more record. Records that do not fit the format are skipped.
    /// - Complexity: O(output)
    public static func porcelainV2(_ data: Data) -> GitStatusSnapshot {
        var head: String?
        var upstream: String?
        var ahead = 0
        var behind = 0
        var sawBranch = false
        var entries: [GitStatusEntry] = []
        let records = data.split(separator: 0, omittingEmptySubsequences: true)
            .map { String(decoding: $0, as: UTF8.self) }
        var index = 0
        while index < records.count {
            let record = records[index]
            index += 1
            if record.hasPrefix("# branch.") {
                sawBranch = true
                let fields = record.dropFirst("# branch.".count).split(separator: " ", maxSplits: 1)
                guard fields.count == 2 else { continue }
                let value = String(fields[1])
                switch fields[0] {
                    case "head": head = value == "(detached)" ? nil : value
                    case "upstream": upstream = value
                    case "ab":
                        let counts = value.split(separator: " ")
                        ahead = counts.first.flatMap { Int($0.dropFirst()) } ?? 0
                        behind = counts.count > 1 ? Int(counts[1].dropFirst()) ?? 0 : 0
                    default: break
                }
                continue
            }
            guard let kind = record.first else { continue }
            let rest = record.dropFirst(2)
            switch kind {
                case "?":
                    entries.append(GitStatusEntry(path: String(rest), status: .untracked))
                case "!":
                    entries.append(GitStatusEntry(path: String(rest), status: .ignored))
                case "1":
                    // XY sub mH mI mW hH hI path
                    let fields = rest.split(separator: " ", maxSplits: 7, omittingEmptySubsequences: false)
                    guard fields.count == 8 else { continue }
                    entries.append(
                        GitStatusEntry(
                            path: String(fields[7]), status: ordinaryStatus(fields[0]),
                            isSubmodule: fields[1].first == "S"))
                case "2":
                    // XY sub mH mI mW hH hI Xscore path, then the original path as the next record.
                    let fields = rest.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: false)
                    guard fields.count == 9, index < records.count else { continue }
                    let original = records[index]
                    index += 1
                    let isCopy = fields[7].first == "C"
                    entries.append(
                        GitStatusEntry(
                            path: String(fields[8]), originalPath: original, status: isCopy ? .added : .renamed,
                            isSubmodule: fields[1].first == "S"))
                case "u":
                    // XY sub m1 m2 m3 mW h1 h2 h3 path
                    let fields = rest.split(separator: " ", maxSplits: 9, omittingEmptySubsequences: false)
                    guard fields.count == 10 else { continue }
                    entries.append(
                        GitStatusEntry(
                            path: String(fields[9]), status: .conflicted, isSubmodule: fields[1].first == "S"))
                default:
                    continue
            }
        }
        let branch = sawBranch ? GitBranchStatus(head: head, upstream: upstream, ahead: ahead, behind: behind) : nil
        return GitStatusSnapshot(branch: branch, entries: entries)
    }

    /// The status of an ordinary (`1`) record from its `XY` field: deletion and addition on either side win over a
    /// modification; a type change counts as a modification.
    private static func ordinaryStatus(_ xy: Substring) -> FileStatus {
        let x = xy.first ?? "."
        let y = xy.dropFirst().first ?? "."
        if x == "D" || y == "D" { return .deleted }
        if x == "A" || y == "A" { return .added }
        if x == "." && y == "." { return .clean }
        return .modified
    }
}

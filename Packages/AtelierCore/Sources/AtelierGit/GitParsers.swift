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

    /// Splits `remote -v` output: `<name>\t<url> (fetch|push)` per line. Each remote's `(fetch)` URL is kept once, in
    /// first-seen order; a push-only remote is left out.
    public static func remotes(_ data: Data) -> [GitRemote] {
        var order: [String] = []
        var fetchURLs: [String: String] = [:]
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            let fields = line.split(separator: "\t", maxSplits: 1)
            guard fields.count == 2, fields[1].hasSuffix("(fetch)") else { continue }
            let name = String(fields[0])
            let url = fields[1].dropLast("(fetch)".count).trimmingCharacters(in: .whitespaces)
            if fetchURLs[name] == nil { order.append(name) }
            fetchURLs[name] = url
        }
        return order.map { GitRemote(name: $0, fetchURL: fetchURLs[$0] ?? "") }
    }

    /// Splits `rev-list --left-right --count` output: `<ahead>\t<behind>` on one line; anything else throws.
    public static func aheadBehind(_ data: Data) throws(GitError) -> (ahead: Int, behind: Int) {
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let fields = text.split(separator: "\t")
        guard fields.count == 2, let ahead = Int(fields[0]), let behind = Int(fields[1]) else {
            throw .commandFailed("could not parse ahead/behind counts from: \(text)")
        }
        return (ahead, behind)
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

    /// The `log` format ``commitChanges(_:)`` reads: a record separator marking each commit, then its id, parents,
    /// author time, author name and subject, each ending in a NUL, the one byte none of them can hold.
    static let commitChangesFormat = "--format=%x1e%H%x00%P%x00%at%x00%an%x00%s"

    /// Splits `log -z --raw --no-abbrev` output in the ``commitChangesFormat``: per commit, a header of five
    /// NUL-terminated fields starting with the record separator, then its raw records, each a NUL-terminated
    /// `:<mode> <mode> <blob> <blob> <status>` followed by one path, or two for a rename or a copy. The first record
    /// of a commit carries a leading newline. Fields are read by position, so a subject or a path holding a
    /// separator, a newline or any other byte but NUL reads intact. A commit whose header is cut short ends the
    /// listing; a record that fits no format is skipped.
    /// - Complexity: O(output)
    public static func commitChanges(_ data: Data) -> [GitCommitChanges] {
        let fields = nulTerminatedFields(data)
        var commits: [GitCommitChanges] = []
        var index = 0
        while index < fields.count {
            guard fields[index].first == 0x1E else {
                index += 1
                continue
            }
            guard index + 5 <= fields.count else { break }
            let id = string(fields[index].dropFirst())
            let parents = string(fields[index + 1]).split(separator: " ").map(String.init)
            let time = TimeInterval(string(fields[index + 2])) ?? 0
            let author = string(fields[index + 3])
            let subject = string(fields[index + 4])
            index += 5
            var changes: [GitFileChange] = []
            while index < fields.count, fields[index].first != 0x1E {
                if let (change, consumed) = rawChange(fields, at: index) {
                    changes.append(change)
                    index += consumed
                } else {
                    index += 1
                }
            }
            commits.append(
                GitCommitChanges(
                    id: id, parentIDs: parents, authorName: author, authorDate: Date(timeIntervalSince1970: time),
                    subject: subject, changes: changes))
        }
        return commits
    }

    /// Splits `diff --raw -z --no-abbrev` output: the raw records of ``commitChanges(_:)`` without commit headers.
    /// - Complexity: O(output)
    public static func rawChanges(_ data: Data) -> [GitFileChange] {
        let fields = nulTerminatedFields(data)
        var changes: [GitFileChange] = []
        var index = 0
        while index < fields.count {
            if let (change, consumed) = rawChange(fields, at: index) {
                changes.append(change)
                index += consumed
            } else {
                index += 1
            }
        }
        return changes
    }

    /// The fields of NUL-terminated output, empty ones kept, since an empty subject or author is still a field.
    private static func nulTerminatedFields(_ data: Data) -> [Data] {
        var fields = data.split(separator: 0, omittingEmptySubsequences: false)
        if fields.last?.isEmpty == true { fields.removeLast() }
        return fields
    }

    private static func string(_ bytes: Data) -> String {
        String(decoding: bytes, as: UTF8.self)
    }

    /// The raw record starting at `fields[index]` and how many fields it spans, or nil when that field starts no
    /// record or its paths are missing. The leading newline git puts before a commit's first record is skipped.
    private static func rawChange(_ fields: [Data], at index: Int) -> (GitFileChange, Int)? {
        var meta = fields[index]
        if meta.first == 0x0A { meta = meta.dropFirst() }
        guard meta.first == UInt8(ascii: ":"), meta.dropFirst().first != UInt8(ascii: ":") else { return nil }
        let parts = string(meta.dropFirst()).split(separator: " ")
        guard parts.count == 5, let letter = parts[4].first else { return nil }
        let oldBlob = blobID(parts[2])
        let newBlob = blobID(parts[3])
        let hasTwoPaths = letter == "R" || letter == "C"
        guard index + (hasTwoPaths ? 2 : 1) < fields.count else { return nil }
        let first = string(fields[index + 1])
        switch letter {
            case "R":
                let change = GitFileChange(
                    status: .renamed, path: string(fields[index + 2]), oldPath: first, oldBlobID: oldBlob,
                    newBlobID: newBlob)
                return (change, 3)
            case "C":
                return (GitFileChange(status: .added, path: string(fields[index + 2]), newBlobID: newBlob), 3)
            case "A":
                return (GitFileChange(status: .added, path: first, newBlobID: newBlob), 2)
            case "D":
                return (GitFileChange(status: .deleted, path: first, oldBlobID: oldBlob), 2)
            default:
                return (GitFileChange(status: .modified, path: first, oldBlobID: oldBlob, newBlobID: newBlob), 2)
        }
    }

    /// A raw record's object id, nil for git's all-zero id: no object on that side, or one not hashed yet.
    private static func blobID(_ field: Substring) -> String? {
        field.allSatisfy { $0 == "0" } ? nil : String(field)
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
                    entries.append(GitStatusEntry(path: String(rest), status: .untracked, worktreeStatus: .untracked))
                case "!":
                    entries.append(GitStatusEntry(path: String(rest), status: .ignored, worktreeStatus: .ignored))
                case "1":
                    // XY sub mH mI mW hH hI path
                    let fields = rest.split(separator: " ", maxSplits: 7, omittingEmptySubsequences: false)
                    guard fields.count == 8 else { continue }
                    let xy = columns(fields[0])
                    entries.append(
                        GitStatusEntry(
                            path: String(fields[7]), status: ordinaryStatus(fields[0]),
                            isSubmodule: fields[1].first == "S", indexStatus: xy.index,
                            worktreeStatus: xy.worktree))
                case "2":
                    // XY sub mH mI mW hH hI Xscore path, then the original path as the next record.
                    let fields = rest.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: false)
                    guard fields.count == 9, index < records.count else { continue }
                    let original = records[index]
                    index += 1
                    let isCopy = fields[7].first == "C"
                    let xy = columns(fields[0])
                    entries.append(
                        GitStatusEntry(
                            path: String(fields[8]), originalPath: original, status: isCopy ? .added : .renamed,
                            isSubmodule: fields[1].first == "S", indexStatus: xy.index,
                            worktreeStatus: xy.worktree))
                case "u":
                    // XY sub m1 m2 m3 mW h1 h2 h3 path
                    let fields = rest.split(separator: " ", maxSplits: 9, omittingEmptySubsequences: false)
                    guard fields.count == 10 else { continue }
                    let xy = columns(fields[0])
                    entries.append(
                        GitStatusEntry(
                            path: String(fields[9]), status: .conflicted, isSubmodule: fields[1].first == "S",
                            indexStatus: xy.index, worktreeStatus: xy.worktree))
                default:
                    continue
            }
        }
        let branch = sawBranch ? GitBranchStatus(head: head, upstream: upstream, ahead: ahead, behind: behind) : nil
        return GitStatusSnapshot(branch: branch, entries: entries)
    }

    /// The two sides of a record's `XY` field. A missing letter reads as unmodified, as ``ordinaryStatus(_:)`` reads
    /// it, and a letter the format does not document as a modification, the most general change.
    private static func columns(_ xy: Substring) -> (index: GitStatusCode, worktree: GitStatusCode) {
        func code(_ letter: Character?) -> GitStatusCode {
            guard let letter else { return .unmodified }
            return GitStatusCode(rawValue: letter) ?? .modified
        }
        return (code(xy.first), code(xy.dropFirst().first))
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

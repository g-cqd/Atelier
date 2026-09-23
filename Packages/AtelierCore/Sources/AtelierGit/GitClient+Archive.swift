import Darwin
public import Foundation
import os

/// Exporting a tree into a private folder, so tools that read files from disk can analyze a git ref's content.
extension GitClient {
    /// The tree `ref` names, as an object id: exactly what an export of `ref` holds, and so a key its analysis can be
    /// cached under whatever folder it was exported to.
    /// - Throws: ``GitError`` when `ref` names no tree, or when the repository's configuration is refused.
    public func treeID(of ref: String) async throws -> String {
        let data = try await run([
            "rev-parse", "--verify", "--quiet", "--end-of-options", "\(try Self.checked(ref))^{tree}"
        ])
        let id = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { throw GitError.commandFailed("\(ref) names no tree") }
        return id
    }

    /// Writes the files of `tree` that `includes` accepts into a new private folder, runs `body` with it, and removes
    /// the folder afterwards, whatever `body` does.
    ///
    /// The export runs `git archive` through this client, so the configuration gate and the isolation flags apply,
    /// and it is kept from running anything a repository could choose:
    /// - A tree is archived, not a commit: `export-subst` only expands its placeholders for a commit, so `$Format:…$`
    ///   stays as committed and no signature program or `git describe` runs.
    /// - Every filter driver defined in any configuration scope is blanked, the user's own included, so a `filter=`
    ///   attribute in the tree starts no clean, smudge or process command; git-lfs's would even reach the network.
    /// - Attributes come from the empty tree (`attr.tree`), not from the archived one, and not from the user's file,
    ///   so `export-ignore` drops no file and no line ending or encoding is converted: the files hold the blobs the
    ///   diff shows, and a finding lands on the line the diff draws. `--worktree-attributes` is what makes git consult
    ///   `attr.tree` at all; it reads that tree before the working tree. A git older than 2.43 ignores `attr.tree` and
    ///   reads the working tree's `.gitattributes` instead, and the repository's own `info/attributes` always applies,
    ///   since git reads it first: either may drop or convert a file, and neither can run a filter.
    /// - Only regular files are written. A symbolic link, which could point a tool at a file outside the export, is
    ///   skipped, and a path that would leave the folder is refused.
    ///
    /// - Parameters:
    ///   - tree: A tree id, as ``treeID(of:)`` returns it.
    ///   - includes: Which repository-relative paths to export; git never reads the others.
    ///   - body: Runs with the folder, which is readable by the user alone and exists only while `body` runs.
    /// - Returns: What `body` returns.
    /// - Throws: ``GitError`` from git, an error from creating or writing the folder, or what `body` throws.
    public func withExportedTree<T: Sendable>(
        _ tree: String, including includes: @Sendable (String) -> Bool,
        _ body: @Sendable (URL) async throws -> T
    ) async throws -> T {
        let folder = try Self.makePrivateFolder()
        do {
            try await export(tree, including: includes, into: folder)
            let result = try await body(folder)
            Self.removeFolder(folder)
            return result
        } catch {
            Self.removeFolder(folder)
            throw error
        }
    }

    /// Paths archived per `git archive` run, so the command line stays far below the system's argument limit.
    static let archiveBatchSize = 1_000

    private func export(
        _ tree: String, including includes: @Sendable (String) -> Bool, into folder: URL
    ) async throws {
        let paths = Self.exportablePaths(try await self.tree(at: tree, isSupported: includes).map(\.relativePath))
        guard !paths.isEmpty else { return }
        let configuration = try await exportConfiguration(emptyTree: Self.emptyTree(matching: tree))
        for start in stride(from: 0, to: paths.count, by: Self.archiveBatchSize) {
            let batch = paths[start ..< min(start + Self.archiveBatchSize, paths.count)]
            let archive = try await run(
                configuration + ["archive", "--worktree-attributes", "--format=tar", try Self.checked(tree), "--"]
                    + batch.map { ":(literal)\($0)" })
            try TarExtractor.extract(archive, into: folder)
        }
    }

    /// The listed paths an export can write faithfully, which leaves out: a path git would refuse on its command line,
    /// with a NUL or a newline; a name that is not UTF-8, which reads back with a replacement character and so names
    /// no file of the tree; and every path that names one file with another on a volume that ignores case or Unicode
    /// normalization, since a tool would read the one written first under the other's name.
    static func exportablePaths(_ paths: [String]) -> [String] {
        let usable = paths.filter { !$0.utf8.contains(0) && !$0.utf8.contains(0x0A) && !$0.contains("\u{FFFD}") }
        let sharing = Dictionary(grouping: usable, by: foldedPath).mapValues(\.count)
        return usable.filter { sharing[foldedPath($0)] == 1 }
    }

    /// `path` as a volume that ignores case and Unicode normalization compares it.
    private static func foldedPath(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping.lowercased()
    }

    /// The `-c` flags that keep an export from converting a file or running a filter: every filter driver defined in
    /// any scope blanked, attributes read from the empty tree, and no user attributes file.
    private func exportConfiguration(emptyTree: String) async throws -> [String] {
        let listing = try await run(["config", "--list", "-z", "--includes", "--name-only"])
        let drivers = Self.filterDrivers(inNameListing: listing)
        return GitConfigPolicy.filterBlankingFlags(for: drivers)
            + ["-c", "attr.tree=\(emptyTree)", "-c", "core.attributesFile=/dev/null"]
    }

    /// The driver names of every `filter.<driver>.<key>` in a `git config --list -z --name-only` listing, in order.
    static func filterDrivers(inNameListing data: Data) -> [String] {
        var drivers: [String] = []
        for field in data.split(separator: 0) {
            let key = String(decoding: field, as: UTF8.self)
            guard key.lowercased().hasPrefix("filter."), let last = key.lastIndex(of: ".") else { continue }
            let first = key.index(key.startIndex, offsetBy: "filter.".count)
            guard first < last else { continue }
            let driver = String(key[first ..< last])
            if !drivers.contains(driver) { drivers.append(driver) }
        }
        return drivers
    }

    /// The empty tree's id in the object format of `tree`: SHA-256's for a 64-character id, SHA-1's otherwise. git
    /// knows the empty tree without storing it, so `attr.tree` resolves it in any repository.
    static func emptyTree(matching tree: String) -> String {
        tree.count == 64
            ? "6ef19b41225c5369f1c104d45d8d85efa9b057b53b14b4b9b939dd74decc5321"
            : "4b825dc642cb6eb9a060e54bf8d69288fbee4904"
    }

    // MARK: - The private folder

    private static let logger = Logger(subsystem: "AtelierGit", category: "Export")

    /// A new folder under the user's temporary directory, created by `mkdtemp`, so it is fresh, unpredictable and
    /// readable by the user alone (mode 0700).
    static func makePrivateFolder() throws -> URL {
        let template = FileManager.default.temporaryDirectory.appending(path: "atelier-export.XXXXXXXX").path
        var bytes = Array(template.utf8CString)
        let created = bytes.withUnsafeMutableBufferPointer { buffer in
            buffer.baseAddress.flatMap { mkdtemp($0) }
        }
        guard created != nil else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let path = String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return URL(filePath: path, directoryHint: .isDirectory)
    }

    /// Removes an export folder; a failure is logged, since the caller's own result or error matters more.
    private static func removeFolder(_ folder: URL) {
        do {
            try FileManager.default.removeItem(at: folder)
        } catch {
            logger.error("Could not remove the export at \(folder.path, privacy: .public): \(error)")
        }
    }
}

/// Writes the regular files of a tar stream, as `git archive --format=tar` writes it, under a folder, and nothing
/// else: no link, no device, no path outside the folder.
enum TarExtractor {
    enum Failure: Error, Equatable {
        /// A header or its data runs past the end of the stream, or a size or record does not parse.
        case truncated
        /// A path that is absolute, empty, or climbs out with `..`.
        case unsafePath(String)
    }

    private static let blockSize = 512

    /// Writes every regular file of `archive` under `folder`, with the owner's permissions only.
    static func extract(_ archive: Data, into folder: URL) throws {
        let bytes = [UInt8](archive)
        var offset = 0
        var nextPath: String?
        var nextSize: Int?
        while offset + blockSize <= bytes.count {
            let header = bytes[offset ..< offset + blockSize]
            if header.allSatisfy({ $0 == 0 }) { return }
            guard let parsedSize = octal(header, at: 124, length: 12) else { throw Failure.truncated }
            let size = nextSize ?? parsedSize
            let dataStart = offset + blockSize
            // Checked before any arithmetic on it: a hostile size must neither trap nor overflow.
            guard size >= 0, size <= bytes.count - dataStart else { throw Failure.truncated }
            let data = bytes[dataStart ..< dataStart + size]
            offset = dataStart + (size + blockSize - 1) / blockSize * blockSize
            switch header[header.startIndex + 156] {
                case UInt8(ascii: "x"):
                    // A pax header for the next entry: its long path or its size.
                    let records = try paxRecords(data)
                    nextPath = records["path"]
                    nextSize = try records["size"]
                        .map { value in
                            guard let size = Int(value), size >= 0 else { throw Failure.truncated }
                            return size
                        }
                    continue
                case UInt8(ascii: "0"), 0:
                    try write(Data(data), to: nextPath ?? name(of: header), under: folder)
                default:
                    // Directories are made as their files need them; links, the global pax header and anything else
                    // are not written.
                    break
            }
            nextPath = nil
            nextSize = nil
        }
    }

    /// The ustar name: the prefix field, a slash, then the name field, each up to its first NUL.
    private static func name(of header: ArraySlice<UInt8>) -> String {
        let name = field(header, at: 0, length: 100)
        let prefix = field(header, at: 345, length: 155)
        return prefix.isEmpty ? name : prefix + "/" + name
    }

    private static func field(_ header: ArraySlice<UInt8>, at start: Int, length: Int) -> String {
        let slice = header[(header.startIndex + start) ..< (header.startIndex + start + length)]
        return String(decoding: slice.prefix { $0 != 0 }, as: UTF8.self)
    }

    /// An octal number field, NUL- or space-terminated; nil unless it holds octal digits only, since `Int(_:radix:)`
    /// would also take a sign.
    private static func octal(_ header: ArraySlice<UInt8>, at start: Int, length: Int) -> Int? {
        let text = field(header, at: start, length: length).trimmingCharacters(in: .whitespaces)
        guard text.utf8.allSatisfy({ (UInt8(ascii: "0") ... UInt8(ascii: "7")).contains($0) }) else { return nil }
        return text.isEmpty ? 0 : Int(text, radix: 8)
    }

    /// The `key=value` records of a pax extended header, each written as `<length> <key>=<value>\n`, where the length
    /// counts the whole record; a record whose length does not reach past its own space to a closing newline, or runs
    /// past the header, is refused.
    private static func paxRecords(_ data: ArraySlice<UInt8>) throws -> [String: String] {
        var records: [String: String] = [:]
        var index = data.startIndex
        while index < data.endIndex {
            guard let space = data[index...].firstIndex(of: UInt8(ascii: " ")),
                let length = Int(String(decoding: data[index ..< space], as: UTF8.self)),
                length > space - index + 1, length <= data.endIndex - index,
                data[index + length - 1] == UInt8(ascii: "\n")
            else { throw Failure.truncated }
            let record = data[(space + 1) ..< (index + length - 1)]
            if let equals = record.firstIndex(of: UInt8(ascii: "=")) {
                records[String(decoding: record[..<equals], as: UTF8.self)] = String(
                    decoding: record[(equals + 1)...], as: UTF8.self)
            }
            index += length
        }
        return records
    }

    /// Writes `data` at the relative `path` under `folder`, refusing a path that is absolute or climbs out, and never
    /// following or replacing what is already there.
    private static func write(_ data: Data, to path: String, under folder: URL) throws {
        let components = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !path.hasPrefix("/"), !components.isEmpty, !components.contains(where: { $0 == ".." || $0 == "." })
        else { throw Failure.unsafePath(path) }
        let file = components.reduce(folder) { $0.appending(path: $1) }
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let descriptor = open(file.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else {
            // Two paths that differ only in case land on one file on a case-insensitive volume; the first one stays.
            if errno == EEXIST { return }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        try handle.write(contentsOf: data)
    }
}

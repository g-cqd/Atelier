public import AemiDiff
import AemiIO
public import AemiRuntime
public import AtelierGit
public import AtelierProcess
import AtelierSyntaxModel
import CryptoKit
public import Foundation
import Synchronization

/// Reads comparison targets through one provider per kind of source; renames need both sides so they stay here.
public struct SourceLoader: SourceReading {
    /// How git is spawned; the app owns the pool behind it.
    public let runner: any ProcessRunner
    /// Where the loader's own blocking calls run: file reads, hashing, `stat` passes and folder scans.
    let offload: any BlockingOffload
    /// Hashes one listed file, on a pool thread.
    let hashFile: FileHasher
    /// Working-tree blob ids kept across reloads, by folder.
    let workingTreeHashes = WorkingTreeHashes()

    /// - Parameters:
    ///   - runner: How git is spawned; the app owns the pool behind it, tests inject a fake.
    ///   - pool: The threads the loader reads, hashes and scans files on, so that no cooperative thread ever waits
    ///     on the disk; the app's own pool.
    public init(runner: any ProcessRunner, pool: BlockingOffloadPool) {
        self.init(runner: runner, offload: pool)
    }

    init(
        runner: any ProcessRunner,
        offload: any BlockingOffload,
        hashFile: @escaping FileHasher = SourceLoader.hashedFile(atPath:format:)
    ) {
        self.runner = runner
        self.offload = offload
        self.hashFile = hashFile
        patches = PatchCache(offload: offload)
    }

    /// Hashes the file at a path for a folder listing, blocking; nil when it cannot be hashed. The loader's own is
    /// ``hashedFile(atPath:format:)``; a test counts the calls and where they run.
    typealias FileHasher = @Sendable (_ path: String, _ format: ObjectFormat) -> HashedFile?

    /// Files above this size are listed but not hashed, so they always count as different.
    public static let maximumHashedSize = 8 * 1024 * 1024
    public static let skippedDirectories: Set<String> = ["node_modules", "DerivedData", "Pods", "Carthage"]
    /// Files a folder listing hands the pool to hash at once: enough to keep every pool thread busy while results
    /// come back, few enough that a large folder queues a handful of jobs rather than one per file.
    public static let hashingConcurrency = 16
    /// Blobs per `cat-file --batch` process; a few processes run side by side for very large selections.
    public static let blobBatchSize = 256
    /// The budget of every git run the loader starts, on the runner's clock: a git that never answers, as one reading
    /// a FIFO a repository's configuration names does, is terminated then instead of holding a pool thread for good.
    /// Generous, since a rename search between distant refs of a large repository can take seconds.
    public static let gitTimeout: Duration = .seconds(60)

    /// Git over `repository` within ``gitTimeout``: every client the loader and its sources run comes from here.
    static func git(_ repository: URL, runner: any ProcessRunner) -> GitClient {
        GitClient(repository: repository, runner: runner, timeout: gitTimeout)
    }

    /// The root of the repository `url` lies in, asked of git within ``gitTimeout``; nil as
    /// ``GitClient/repositoryRoot(containing:runner:timeout:isolation:gate:)`` gives it.
    static func repositoryRoot(containing url: URL, runner: any ProcessRunner) async -> URL? {
        await GitClient.repositoryRoot(containing: url, runner: runner, timeout: gitTimeout)
    }

    /// Extensions that are never text; everything else is listed and shown, as code when the language is known
    /// and as plain text otherwise. Binary content slipping through is caught when it is read.
    public static let binaryExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "bmp", "tiff", "tif", "ico", "icns", "pdf", "psd", "ai",
        "zip", "gz", "tgz", "bz2", "xz", "7z", "tar", "jar", "dmg", "pkg", "ipa", "apk", "car", "nib", "mlmodel",
        "mlmodelc", "realm", "sqlite", "sqlite3", "db", "bin", "dat", "exe", "dll", "dylib", "so", "a", "o", "class",
        "pyc", "wasm", "mp3", "mp4", "m4a", "m4v", "mov", "avi", "wav", "aac", "flac", "ogg", "ttf", "otf", "woff",
        "woff2", "eot", "ttc", "mtl", "obj", "usdz", "scn", "reality"
    ]

    private let patches: PatchCache

    public static func isSupported(path: String) -> Bool {
        !binaryExtensions.contains(pathExtension(of: path).lowercased())
    }

    /// The extension of `path`'s last component, as `URL.pathExtension` gives it, without building a URL: a URL made
    /// from a relative path resolves it against the working directory, a `getcwd` for each of the thousands of paths
    /// a listing checks. A stem of dots only (`..x`) has no extension, and neither has one with a space in it.
    static func pathExtension(of path: String) -> Substring {
        var trimmed = path[...]
        while trimmed.last == "/" { trimmed = trimmed.dropLast() }
        let name = trimmed[(trimmed.lastIndex(of: "/").map { trimmed.index(after: $0) } ?? trimmed.startIndex)...]
        guard let dot = name.lastIndex(of: "."), name[..<dot].contains(where: { $0 != "." }) else { return "" }
        let pathExtension = name[name.index(after: dot)...]
        return pathExtension.contains(" ") ? "" : pathExtension
    }

    /// Text of a file's bytes, decoded as UTF-8 in one pass: an invalid sequence becomes U+FFFD, and a leading
    /// byte-order mark is dropped, as Foundation's UTF-8 decoding drops it. A file with a NUL anywhere in it is
    /// binary and becomes one line naming its size, so the diff still shows that it changed. The whole file is
    /// searched, not its first 8 KiB: a NUL anywhere means the bytes are not text a diff can show, whatever the first
    /// lines look like. The scan costs about 0.3 ms per 8 MiB, small beside the read that precedes it. AtelierSearch
    /// keeps its narrower probe (`binaryProbeLength`, the first 8 KiB) on purpose, as git and the file enumerator
    /// judge a file binary.
    public static func text(from data: Data) -> String {
        if let unicode = TextEncoding.wideUnicode(of: data) {
            return String(data: data, encoding: unicode) ?? binaryPlaceholder(for: data)
        }
        if containsNUL(data) {
            return binaryPlaceholder(for: data)
        }
        let body = data.starts(with: utf8ByteOrderMark) ? data.dropFirst(utf8ByteOrderMark.count) : data
        if let text = String(validating: body, as: UTF8.self) { return text }
        // Not UTF-8: every byte keeps its own character, so an edit anywhere stays visible.
        return String(data: body, encoding: .isoLatin1) ?? String(decoding: body, as: UTF8.self)
    }

    /// The text shown for bytes a diff cannot show: their exact size and their blob id, so an edit always changes it.
    static func binaryPlaceholder(for data: Data) -> String {
        "(binary file, \(data.count) bytes, blob \(blobID(of: data).prefix(12)))\n"
    }

    private static let utf8ByteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]

    /// Whether any byte of `data` is zero, found with `memchr` over the whole buffer: `Data.contains` compares one
    /// byte at a time and is about 100 times slower. An empty buffer has no base address and no NUL.
    private static func containsNUL(_ data: Data) -> Bool {
        data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return false }
            return memchr(base, 0, buffer.count) != nil
        }
    }

    public func repositoryInfo(containing url: URL) async -> RepositoryInfo? {
        guard let root = await Self.repositoryRoot(containing: url, runner: runner) else { return nil }
        return try? await Self.git(root, runner: runner).info()
    }

    public func configurationRefusal(containing url: URL) async -> GitConfigRefusal? {
        await GitClient.configurationRefusal(containing: url, runner: runner, timeout: Self.gitTimeout)
    }

    public func entries(of source: ComparisonSource) async throws -> [GitTreeEntry] {
        try await provider(for: source).entries()
    }

    public func ignoredEntries(of source: ComparisonSource) async throws -> [GitTreeEntry] {
        try await provider(for: source).ignoredEntries()
    }

    /// The text a diff shows for `entry`: its file's, or for a submodule the commit it records, as `git diff` shows.
    public func content(of entry: GitTreeEntry, in source: ComparisonSource) async throws -> String {
        if entry.isSubmodule { return GitTreeEntry.submoduleText(commit: entry.blobID ?? "") }
        return try await provider(for: source).content(of: entry)
    }

    public func contents(of entries: [GitTreeEntry], in source: ComparisonSource) async throws -> [String: String] {
        let submodules = entries.filter(\.isSubmodule)
        var texts = try await provider(for: source).contents(of: entries.filter { !$0.isSubmodule })
        for entry in submodules {
            texts[entry.relativePath] = GitTreeEntry.submoduleText(commit: entry.blobID ?? "")
        }
        return texts
    }

    private func provider(for source: ComparisonSource) -> any SourceProvider {
        switch source {
            case .file(let url): FileSource(url: url, offload: offload)
            case .directory(let url):
                DirectorySource(
                    root: url,
                    runner: runner,
                    offload: offload,
                    hashFile: hashFile,
                    hashes: workingTreeHashes
                )
            case .gitRef(let repository, let ref): GitRefSource(repository: repository, ref: ref, runner: runner)
            case .patch(let url, let side): PatchSource(url: url, side: side, cache: patches)
        }
    }

    public func resolve(ref: String, in repository: URL) async throws -> String {
        try await Self.git(repository, runner: runner).resolve(ref: ref)
    }

    public func renames(from left: ComparisonSource, to right: ComparisonSource) async -> [String: String] {
        switch (left, right) {
            case (.gitRef(let repository, let from), .gitRef(let other, let to)) where repository == other:
                (try? await Self.git(repository, runner: runner).renames(from: from, to: to)) ?? [:]
            case (.gitRef(let repository, let from), .directory(let folder))
            where repository.standardizedFileURL == folder.standardizedFileURL:
                (try? await Self.git(repository, runner: runner).renames(from: from, to: nil)) ?? [:]
            case (.patch(let url, .old), .patch(let other, .new)) where url == other:
                Dictionary(
                    ((try? await patches.patch(at: url))?.files ?? []).filter(\.isRename)
                        .compactMap { file in file.oldPath.flatMap { old in file.newPath.map { (old, $0) } } },
                    uniquingKeysWith: { first, _ in first }
                )
            default:
                [:]
        }
    }

    // MARK: Hashing

    /// The object id git would assign to `data` as a blob in a repository of `format`, so filesystem files compare
    /// against `git ls-tree` output.
    public static func blobID(of data: Data, format: ObjectFormat = .sha1) -> String {
        switch format {
            case .sha1: blobID(of: data, hashing: Insecure.SHA1())
            case .sha256: blobID(of: data, hashing: SHA256())
        }
    }

    private static func blobID(of data: Data, hashing hasher: some HashFunction) -> String {
        var hasher = hasher
        hasher.update(data: Data("blob \(data.count)\0".utf8))
        hasher.update(data: data)
        return Self.hex(hasher.finalize())
    }

    private static let hexDigits: [UInt8] = Array("0123456789abcdef".utf8)

    /// Lowercase hex of a digest without going through `String(format:)` per byte.
    static func hex(_ digest: some Sequence<UInt8>) -> String {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(40)
        for byte in digest {
            bytes.append(hexDigits[Int(byte >> 4)])
            bytes.append(hexDigits[Int(byte & 0x0F)])
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// Hashes a file as git would store it, read in chunks with `pread` rather than mapped: another process can
    /// truncate a working-tree file at any moment, and touching a mapped page past the new end raises SIGBUS, where
    /// a short read is only an error. The size comes from the open descriptor, not from an earlier scan.
    /// - Parameter path: The file to hash.
    /// - Returns: The hex git blob id of the file's current contents.
    /// - Throws: `IOError` when the file cannot be opened, measured or read to its end.
    public static func blobID(atPath path: String) throws -> String {
        let file = try PosixFile(path: path, mode: .readOnly)
        defer { file.close() }
        return try blobID(of: file)
    }

    /// Salted with the path: files a patch carries without content, such as pure renames or mode changes, would
    /// otherwise all share one blob id and be paired as renames of each other.
    public static func patchBlobID(path: String, text: String) -> String {
        blobID(of: Data((path + "\0" + text).utf8))
    }
}

/// One kind of comparison target: how its files are listed and read.
public protocol SourceProvider: Sendable {
    func entries() async throws -> [GitTreeEntry]
    /// Files the source leaves out of `entries()` because they are ignored; empty unless the source knows the notion.
    func ignoredEntries() async throws -> [GitTreeEntry]
    func content(of entry: GitTreeEntry) async throws -> String
    func contents(of entries: [GitTreeEntry]) async throws -> [String: String]
}

extension SourceProvider {
    public func ignoredEntries() async throws -> [GitTreeEntry] {
        []
    }

    public func contents(of entries: [GitTreeEntry]) async throws -> [String: String] {
        let pairs = try await mapConcurrently(entries, limit: SourceLoader.hashingConcurrency) { entry in
            (entry.relativePath, try await content(of: entry))
        }
        return Dictionary(pairs, uniquingKeysWith: { first, _ in first })
    }
}

public struct FileSource: SourceProvider {
    public let url: URL
    let offload: any BlockingOffload

    /// The file as one entry, sized and hashed in one blocking call on the pool; a file that cannot be hashed is
    /// listed without a blob id, as a folder lists it.
    public func entries() async throws -> [GitTreeEntry] {
        let url = url
        return [
            try await offload.run {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                let blobID = SourceLoader.hashedFile(atPath: url.path(percentEncoded: false))?.blobID
                return GitTreeEntry(relativePath: url.lastPathComponent, blobID: blobID, size: size)
            }
        ]
    }

    public func content(of entry: GitTreeEntry) async throws -> String {
        SourceLoader.text(from: try await Self.read(url, on: offload))
    }

    /// The file's bytes, copied with `pread` on `offload`; see ``SourceLoader/blobID(atPath:)`` for why not mapped.
    static func read(_ url: URL, on offload: any BlockingOffload) async throws -> Data {
        let path = url.path(percentEncoded: false)
        return try await offload.run { try SourceLoader.contents(atPath: path) }
    }
}

public struct GitRefSource: SourceProvider {
    public let repository: URL
    public let ref: String
    public let runner: any ProcessRunner

    public func entries() async throws -> [GitTreeEntry] {
        try await SourceLoader.git(repository, runner: runner)
            .tree(at: ref, isSupported: SourceLoader.isSupported(path:))
    }

    public func content(of entry: GitTreeEntry) async throws -> String {
        SourceLoader.text(from: try await SourceLoader.git(repository, runner: runner).blob(entry.blobID ?? ""))
    }

    /// Blobs are fetched through one `cat-file --batch` process per batch instead of one process per file.
    public func contents(of entries: [GitTreeEntry]) async throws -> [String: String] {
        let client = SourceLoader.git(repository, runner: runner)
        let ids = Array(Set(entries.compactMap(\.blobID)))
        let batches = stride(from: 0, to: ids.count, by: SourceLoader.blobBatchSize)
            .map { Array(ids[$0 ..< min($0 + SourceLoader.blobBatchSize, ids.count)]) }
        let blobs = try await mapConcurrently(batches, limit: 3) { try await client.blobs($0) }
            .reduce(into: [:]) { $0.merge($1) { first, _ in first } }
        return Dictionary(
            entries.map { entry in
                (entry.relativePath, entry.blobID.flatMap { blobs[$0] }.map(SourceLoader.text(from:)) ?? "")
            },
            uniquingKeysWith: { first, _ in first }
        )
    }
}

public struct PatchSource: SourceProvider {
    public let url: URL
    public let side: ComparisonSource.PatchSide
    public let cache: PatchCache

    /// Each file of the patch on this side, with the mode the patch records for it, so a mode-only change differs.
    public func entries() async throws -> [GitTreeEntry] {
        let texts = try await cache.entry(at: url).texts(side: side)
        let modes = texts.modes
        return texts.ordered
            .map { path, text in
                GitTreeEntry(
                    relativePath: path,
                    blobID: SourceLoader.patchBlobID(path: path, text: text),
                    size: text.utf8.count,
                    mode: modes[path]
                )
            }
    }

    public func content(of entry: GitTreeEntry) async throws -> String {
        try await cache.entry(at: url).texts(side: side).byPath[entry.relativePath] ?? ""
    }

    public func contents(of entries: [GitTreeEntry]) async throws -> [String: String] {
        let byPath = try await cache.entry(at: url).texts(side: side).byPath
        return Dictionary(
            entries.compactMap { entry in byPath[entry.relativePath].map { (entry.relativePath, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
    }
}

/// Parsed patches by file, kept as long as the file's modification date is unchanged, with both sides' documents
/// reconstructed once and indexed by path: a comparison asks for every file's text at least twice.
public final class PatchCache: Sendable {
    /// One side's reconstructed texts, in patch order and by path.
    public struct SideTexts: Sendable {
        public var ordered: [(path: String, text: String)]
        public var byPath: [String: String]
        /// The mode the patch records for each path that has one.
        public var modes: [String: String] = [:]
    }

    /// A parsed patch with its reconstructed sides.
    public struct Entry: Sendable {
        public let patch: UnifiedPatch
        public let old: SideTexts
        public let new: SideTexts

        public func texts(side: ComparisonSource.PatchSide) -> SideTexts {
            side == .old ? old : new
        }

        init(patch: UnifiedPatch) {
            self.patch = patch
            var old = SideTexts(ordered: [], byPath: [:])
            var new = SideTexts(ordered: [], byPath: [:])
            for file in patch.files {
                let texts = file.isBinary ? Self.binaryTexts(of: file) : file.reconstructedTexts
                if let path = file.oldPath, let text = texts.old, old.byPath[path] == nil {
                    old.ordered.append((path, text))
                    old.byPath[path] = text
                    old.modes[path] = file.oldMode
                }
                if let path = file.newPath, let text = texts.new, new.byPath[path] == nil {
                    new.ordered.append((path, text))
                    new.byPath[path] = text
                    new.modes[path] = file.newMode
                }
            }
            self.old = old
            self.new = new
        }

        /// A binary file's sides: the patch carries no text, so each side names its object when the patch's
        /// `index` line does, or which version it is, and the two differ as the files do.
        static func binaryTexts(of file: UnifiedPatch.FileChange) -> (old: String?, new: String?) {
            func text(_ object: String?, _ version: String) -> String {
                "(binary file, \(object.map { "object \($0)" } ?? "\(version) version"): the patch carries no text)\n"
            }
            return (
                file.oldPath.map { _ in text(file.oldObjectID, "old") },
                file.newPath.map { _ in text(file.newObjectID, "new") }
            )
        }
    }

    private let entries = Mutex<[URL: (modified: Date?, entry: Entry)]>([:])
    /// Where a patch file is read.
    private let offload: any BlockingOffload

    init(offload: any BlockingOffload) {
        self.offload = offload
    }

    public func patch(at url: URL) async throws -> UnifiedPatch {
        try await entry(at: url).patch
    }

    public func entry(at url: URL) async throws -> Entry {
        let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        if let cached = entries.withLock({ $0[url] }), cached.modified == modified { return cached.entry }
        let parsed = try await Self.parse(at: url, readingOn: offload)
        entries.withLock { $0[url] = (modified, parsed) }
        return parsed
    }

    /// The patch is read on the pool and parsed here, off the caller's actor.
    @concurrent
    private static func parse(at url: URL, readingOn offload: any BlockingOffload) async throws -> Entry {
        let data = try await offload.run { try Data(contentsOf: url) }
        // A byte that is not UTF-8, in a file's line or a mail header around the patch, becomes U+FFFD instead of
        // failing the whole patch.
        return Entry(patch: UnifiedPatch(parsing: String(decoding: data, as: UTF8.self)))
    }
}

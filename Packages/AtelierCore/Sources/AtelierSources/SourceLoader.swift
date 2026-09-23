import AemiIO
public import AemiRuntime
public import AtelierDiff
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

    /// - Parameters:
    ///   - runner: How git is spawned; the app owns the pool behind it, tests inject a fake.
    ///   - pool: The threads the loader reads, hashes and scans files on, so that no cooperative thread ever waits
    ///     on the disk; the app's own pool.
    public init(runner: any ProcessRunner, pool: BlockingOffloadPool) {
        self.init(runner: runner, offload: pool)
    }

    init(
        runner: any ProcessRunner, offload: any BlockingOffload,
        hashFile: @escaping FileHasher = SourceLoader.readableBlobID(atPath:)
    ) {
        self.runner = runner
        self.offload = offload
        self.hashFile = hashFile
        patches = PatchCache(offload: offload)
    }

    /// Hashes the file at a path, blocking: its git blob id, or nil when it cannot be read. The loader's own is
    /// ``readableBlobID(atPath:)``; a test counts the calls and where they run.
    typealias FileHasher = @Sendable (_ path: String) -> String?

    /// The git blob id of the file at `path`, or nil when it cannot be read to its end: it vanished, shrank or is
    /// not readable since it was listed.
    static func readableBlobID(atPath path: String) -> String? {
        try? blobID(atPath: path)
    }

    /// Files above this size are listed but not hashed, so they always count as different.
    public static let maximumHashedSize = 8 * 1024 * 1024
    public static let skippedDirectories: Set<String> = ["node_modules", "DerivedData", "Pods", "Carthage"]
    /// Files a folder listing hands the pool to hash at once: enough to keep every pool thread busy while results
    /// come back, few enough that a large folder queues a handful of jobs rather than one per file.
    public static let hashingConcurrency = 16
    /// Blobs per `cat-file --batch` process; a few processes run side by side for very large selections.
    public static let blobBatchSize = 256

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
        !binaryExtensions.contains(URL(filePath: path).pathExtension.lowercased())
    }

    /// Text of a file's bytes; a binary file, recognised by a NUL among its first bytes, becomes one line
    /// naming its size so the diff still shows that it changed.
    public static func text(from data: Data) -> String {
        if data.prefix(8192).contains(0) {
            return "(binary file, \(data.count.formatted(.byteCount(style: .file))))\n"
        }
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    public func repositoryInfo(containing url: URL) async -> RepositoryInfo? {
        guard let root = await GitClient.repositoryRoot(containing: url, runner: runner) else { return nil }
        return try? await GitClient(repository: root, runner: runner).info()
    }

    public func entries(of source: ComparisonSource) async throws -> [GitTreeEntry] {
        try await provider(for: source).entries()
    }

    public func ignoredEntries(of source: ComparisonSource) async throws -> [GitTreeEntry] {
        try await provider(for: source).ignoredEntries()
    }

    public func content(of entry: GitTreeEntry, in source: ComparisonSource) async throws -> String {
        try await provider(for: source).content(of: entry)
    }

    public func contents(of entries: [GitTreeEntry], in source: ComparisonSource) async throws -> [String: String] {
        try await provider(for: source).contents(of: entries)
    }

    private func provider(for source: ComparisonSource) -> any SourceProvider {
        switch source {
            case .file(let url): FileSource(url: url, offload: offload)
            case .directory(let url):
                DirectorySource(root: url, runner: runner, offload: offload, hashFile: hashFile)
            case .gitRef(let repository, let ref): GitRefSource(repository: repository, ref: ref, runner: runner)
            case .patch(let url, let side): PatchSource(url: url, side: side, cache: patches)
        }
    }

    public func resolve(ref: String, in repository: URL) async throws -> String {
        try await GitClient(repository: repository, runner: runner).resolve(ref: ref)
    }

    public func renames(from left: ComparisonSource, to right: ComparisonSource) async -> [String: String] {
        switch (left, right) {
            case (.gitRef(let repository, let from), .gitRef(let other, let to)) where repository == other:
                (try? await GitClient(repository: repository, runner: runner).renames(from: from, to: to)) ?? [:]
            case (.gitRef(let repository, let from), .directory(let folder))
            where repository.standardizedFileURL == folder.standardizedFileURL:
                (try? await GitClient(repository: repository, runner: runner).renames(from: from, to: nil)) ?? [:]
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

    /// The object id git would assign to `data` as a blob, so filesystem files compare against `git ls-tree` output.
    public static func blobID(of data: Data) -> String {
        var hasher = Insecure.SHA1()
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
                let blobID =
                    size <= SourceLoader.maximumHashedSize
                    ? SourceLoader.readableBlobID(atPath: url.path(percentEncoded: false)) : nil
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

public struct DirectorySource: SourceProvider {
    public let root: URL
    public let runner: any ProcessRunner
    let offload: any BlockingOffload
    let hashFile: SourceLoader.FileHasher

    /// Inside a repository, the folder as git sees it: tracked and untracked files, dotfiles included, nothing
    /// git ignores. Elsewhere, a folder scan that leaves hidden files out. The `stat` pass, the scan and every hash
    /// run on the pool.
    ///
    /// A file that cannot be hashed, because it vanished, shrank or is not readable since it was listed, is listed
    /// without a blob id, so it counts as changed and is read when shown, instead of failing the whole folder.
    /// - Throws: `CancellationError` when the task is cancelled, even after the last file is hashed: a cancelled
    ///   listing never passes for a finished one, empty or partial.
    @concurrent
    public func entries() async throws -> [GitTreeEntry] {
        let files =
            if let git = await gitClient() {
                try await Self.stat(try await git.workingTreePaths(), under: root, on: offload)
            } else {
                try await Self.scan(root, on: offload)
            }
        let entries = try await mapConcurrently(files, limit: SourceLoader.hashingConcurrency) {
            [offload, hashFile] file in
            let blobID =
                file.size <= SourceLoader.maximumHashedSize ? try await offload.run { hashFile(file.fullPath) } : nil
            return GitTreeEntry(relativePath: file.relativePath, blobID: blobID, size: file.size)
        }
        try Task.checkCancellation()
        return entries
    }

    /// Files git ignores, listed but neither hashed nor sized: they exist on this side alone, so there is nothing
    /// to compare them with, and a tree full of build output holds tens of thousands of them.
    @concurrent
    public func ignoredEntries() async throws -> [GitTreeEntry] {
        guard let git = await gitClient() else { return [] }
        return try await git.ignoredPaths()
            .filter { SourceLoader.isSupported(path: $0) && !Self.liesUnderSkippedDirectory($0) }
            .map { GitTreeEntry(relativePath: $0, blobID: nil, size: 0) }
    }

    public func content(of entry: GitTreeEntry) async throws -> String {
        SourceLoader.text(from: try await FileSource.read(root.appending(path: entry.relativePath), on: offload))
    }

    private struct File: Sendable {
        let fullPath: String
        let relativePath: String
        let size: Int
    }

    /// Paths `stat`ed per blocking job: one job for most folders, and a cancellation lands between two jobs.
    private static let statBatchSize = 1024

    /// Git run in this folder, when it lies in a repository: `ls-files` then lists paths relative to the folder.
    private func gitClient() async -> GitClient? {
        await GitClient.repositoryRoot(containing: root, runner: runner) == nil
            ? nil : GitClient(repository: root, runner: runner)
    }

    /// ``stat(_:under:)`` on `offload`, in batches of ``statBatchSize`` paths.
    private static func stat(_ paths: [String], under root: URL, on offload: any BlockingOffload) async throws
        -> [File]
    {
        let batches = stride(from: 0, to: paths.count, by: statBatchSize)
            .map { Array(paths[$0 ..< min($0 + statBatchSize, paths.count)]) }
        return try await mapConcurrently(batches, limit: 2) { batch in
            try await offload.run { stat(batch, under: root) }
        }
        .flatMap(\.self)
    }

    /// Keeps the regular, supported files among `paths`: an index entry whose file is gone, a submodule or an
    /// unsupported extension is left out, as is anything under a directory the folder scan would skip.
    private static func stat(_ paths: [String], under root: URL) -> [File] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        var files: [File] = []
        files.reserveCapacity(paths.count)
        for path in paths {
            guard SourceLoader.isSupported(path: path), !liesUnderSkippedDirectory(path) else { continue }
            let url = root.appending(path: path)
            guard let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            files.append(
                File(
                    fullPath: url.standardizedFileURL.path(percentEncoded: false), relativePath: path,
                    size: values.fileSize ?? 0))
        }
        return files
    }

    private static func liesUnderSkippedDirectory(_ path: String) -> Bool {
        path.split(separator: "/").dropLast().contains { SourceLoader.skippedDirectories.contains(String($0)) }
    }

    /// ``scan(_:until:)`` on `offload`; cancelling the task stops the scan at its next entry.
    private static func scan(_ root: URL, on offload: any BlockingOffload) async throws -> [File] {
        let cancellation = CancellationFlag()
        return try await withTaskCancellationHandler {
            try await offload.run { try scan(root, until: cancellation) }
        } onCancel: {
            cancellation.raise()
        }
    }

    /// The supported regular files under `root`, hidden files, package contents and skipped directories left out.
    /// - Throws: `CancellationError` once `cancellation` is raised.
    private static func scan(_ root: URL, until cancellation: CancellationFlag) throws -> [File] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .fileSizeKey, .nameKey]
        guard
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            )
        else {
            throw CocoaError(.fileReadNoSuchFile)
        }

        let rootPath = root.standardizedFileURL.path(percentEncoded: false)
        var files: [File] = []
        while let url = enumerator.nextObject() as? URL {
            if cancellation.isRaised { throw CancellationError() }
            let values = try url.resourceValues(forKeys: keys)
            if values.isDirectory == true {
                if SourceLoader.skippedDirectories.contains(values.name ?? "") { enumerator.skipDescendants() }
                continue
            }
            guard values.isRegularFile == true, SourceLoader.isSupported(path: url.lastPathComponent) else { continue }
            let fullPath = url.standardizedFileURL.path(percentEncoded: false)
            let relativePath = String(String(fullPath.dropFirst(rootPath.count)).trimmingPrefix("/"))
            files.append(File(fullPath: fullPath, relativePath: relativePath, size: values.fileSize ?? 0))
        }
        return files
    }
}

public struct GitRefSource: SourceProvider {
    public let repository: URL
    public let ref: String
    public let runner: any ProcessRunner

    public func entries() async throws -> [GitTreeEntry] {
        try await GitClient(repository: repository, runner: runner)
            .tree(at: ref, isSupported: SourceLoader.isSupported(path:))
    }

    public func content(of entry: GitTreeEntry) async throws -> String {
        SourceLoader.text(from: try await GitClient(repository: repository, runner: runner).blob(entry.blobID ?? ""))
    }

    /// Blobs are fetched through one `cat-file --batch` process per batch instead of one process per file.
    public func contents(of entries: [GitTreeEntry]) async throws -> [String: String] {
        let client = GitClient(repository: repository, runner: runner)
        let ids = Array(Set(entries.compactMap(\.blobID)))
        let batches = stride(from: 0, to: ids.count, by: SourceLoader.blobBatchSize)
            .map { Array(ids[$0 ..< min($0 + SourceLoader.blobBatchSize, ids.count)]) }
        let blobs = try await mapConcurrently(batches, limit: 3) { try await client.blobs($0) }
            .reduce(into: [:]) { $0.merge($1) { first, _ in first } }
        return Dictionary(
            entries.map { entry in
                (entry.relativePath, entry.blobID.flatMap { blobs[$0] }.map(SourceLoader.text(from:)) ?? "")
            }, uniquingKeysWith: { first, _ in first })
    }
}

public struct PatchSource: SourceProvider {
    public let url: URL
    public let side: ComparisonSource.PatchSide
    public let cache: PatchCache

    public func entries() async throws -> [GitTreeEntry] {
        try await cache.entry(at: url).texts(side: side).ordered
            .map { path, text in
                GitTreeEntry(
                    relativePath: path, blobID: SourceLoader.patchBlobID(path: path, text: text), size: text.utf8.count)
            }
    }

    public func content(of entry: GitTreeEntry) async throws -> String {
        try await cache.entry(at: url).texts(side: side).byPath[entry.relativePath] ?? ""
    }

    public func contents(of entries: [GitTreeEntry]) async throws -> [String: String] {
        let byPath = try await cache.entry(at: url).texts(side: side).byPath
        return Dictionary(
            entries.compactMap { entry in byPath[entry.relativePath].map { (entry.relativePath, $0) } },
            uniquingKeysWith: { first, _ in first })
    }
}

/// Parsed patches by file, kept as long as the file's modification date is unchanged, with both sides' documents
/// reconstructed once and indexed by path: a comparison asks for every file's text at least twice.
public final class PatchCache: Sendable {
    /// One side's reconstructed texts, in patch order and by path.
    public struct SideTexts: Sendable {
        public var ordered: [(path: String, text: String)]
        public var byPath: [String: String]
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
            for file in patch.files where !file.isBinary {
                let texts = file.reconstructedTexts
                if let path = file.oldPath, let text = texts.old, old.byPath[path] == nil {
                    old.ordered.append((path, text))
                    old.byPath[path] = text
                }
                if let path = file.newPath, let text = texts.new, new.byPath[path] == nil {
                    new.ordered.append((path, text))
                    new.byPath[path] = text
                }
            }
            self.old = old
            self.new = new
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
        Entry(patch: UnifiedPatch(parsing: try await offload.run { try String(contentsOf: url, encoding: .utf8) }))
    }
}

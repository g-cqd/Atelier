import AemiIO
public import AtelierDiff
public import AtelierGit
public import AtelierProcess
import AtelierSyntaxModel
import CryptoKit
public import Foundation
import Synchronization

import func AemiRuntime.mapConcurrently

/// Reads comparison targets through one provider per kind of source; renames need both sides so they stay here.
public struct SourceLoader: SourceReading {
    /// How git is spawned; the app owns the pool behind it.
    public let runner: any ProcessRunner

    public init(runner: any ProcessRunner) {
        self.runner = runner
    }

    /// Files above this size are listed but not hashed, so they always count as different.
    public static let maximumHashedSize = 8 * 1024 * 1024
    public static let skippedDirectories: Set<String> = ["node_modules", "DerivedData", "Pods", "Carthage"]
    /// Files hashed at once during a folder scan; hashing is I/O bound so it scales past the core count.
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

    private let patches = PatchCache()

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
            case .file(let url): FileSource(url: url)
            case .directory(let url): DirectorySource(root: url, runner: runner)
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
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Hashes a file through a read-only memory mapping, so no copy of the contents is made.
    /// Hashes a file through a read-only memory mapping, so no copy of its contents is made. The length comes from
    /// the open descriptor, not from `size`: a file truncated between the directory scan and this hash would
    /// otherwise be mapped past its end, and touching such a page raises SIGBUS. A truncation after the descriptor
    /// is measured is the one window that remains.
    /// - Parameters:
    ///   - path: The file to hash.
    ///   - size: The size the scan saw; only used to skip the mapping of an empty file.
    /// - Returns: The hex git blob id of the file's current contents.
    /// - Throws: `IOError` when the file cannot be opened, measured or mapped.
    public static func blobID(atPath path: String, size: Int) throws -> String {
        var hasher = Insecure.SHA1()
        guard size > 0 else {
            hasher.update(data: Data("blob 0\0".utf8))
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }
        let file = try PosixFile(path: path, mode: .readOnly)
        defer { file.close() }
        let count = try file.fileSize()
        hasher.update(data: Data("blob \(count)\0".utf8))
        if count > 0 {
            let map = try RawFileMap(fileDescriptor: file.fileDescriptor, capacity: count)
            // The whole file is read once, front to back: let the kernel page it in ahead of the hash.
            map.prefetch(offset: 0, length: count)
            map.withRegion(offset: 0, count: count) { region in
                region.withUnsafeBytes { hasher.update(bufferPointer: $0) }
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
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

    public func entries() async throws -> [GitTreeEntry] {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let blobID =
            size <= SourceLoader.maximumHashedSize
            ? try await Self.blobID(atPath: url.path(percentEncoded: false), size: size) : nil
        return [GitTreeEntry(relativePath: url.lastPathComponent, blobID: blobID, size: size)]
    }

    public func content(of entry: GitTreeEntry) async throws -> String {
        SourceLoader.text(from: try await Self.read(url))
    }

    @concurrent
    public static func blobID(atPath path: String, size: Int) async throws -> String {
        try SourceLoader.blobID(atPath: path, size: size)
    }

    @concurrent
    public static func read(_ url: URL) async throws -> Data {
        try Data(contentsOf: url)
    }
}

public struct DirectorySource: SourceProvider {
    public let root: URL
    public let runner: any ProcessRunner

    /// Inside a repository, the folder as git sees it: tracked and untracked files, dotfiles included, nothing
    /// git ignores. Elsewhere, a folder scan that leaves hidden files out.
    @concurrent
    public func entries() async throws -> [GitTreeEntry] {
        let files =
            if let git = await gitClient() {
                try Self.stat(try await git.workingTreePaths(), under: root)
            } else {
                try Self.scan(root)
            }
        return try await mapConcurrently(files, limit: SourceLoader.hashingConcurrency) { file in
            let blobID =
                file.size <= SourceLoader.maximumHashedSize
                ? try SourceLoader.blobID(atPath: file.fullPath, size: file.size) : nil
            return GitTreeEntry(relativePath: file.relativePath, blobID: blobID, size: file.size)
        }
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
        SourceLoader.text(from: try await FileSource.read(root.appending(path: entry.relativePath)))
    }

    private struct File: Sendable {
        let fullPath: String
        let relativePath: String
        let size: Int
    }

    /// Git run in this folder, when it lies in a repository: `ls-files` then lists paths relative to the folder.
    private func gitClient() async -> GitClient? {
        await GitClient.repositoryRoot(containing: root, runner: runner) == nil
            ? nil : GitClient(repository: root, runner: runner)
    }

    /// Keeps the regular, supported files among `paths`: an index entry whose file is gone, a submodule or an
    /// unsupported extension is left out, as is anything under a directory the folder scan would skip.
    private static func stat(_ paths: [String], under root: URL) throws -> [File] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        var files: [File] = []
        files.reserveCapacity(paths.count)
        for path in paths {
            try Task.checkCancellation()
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

    private static func scan(_ root: URL) throws -> [File] {
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
            try Task.checkCancellation()
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
        try await cache.patch(at: url).files
            .compactMap { file in
                guard !file.isBinary, let path = path(of: file) else { return nil }
                let text = text(of: file)
                return GitTreeEntry(
                    relativePath: path, blobID: SourceLoader.patchBlobID(path: path, text: text), size: text.utf8.count)
            }
    }

    public func content(of entry: GitTreeEntry) async throws -> String {
        try await cache.patch(at: url).files.first { path(of: $0) == entry.relativePath }.map(text(of:)) ?? ""
    }

    private func path(of file: UnifiedPatch.FileChange) -> String? {
        side == .old ? file.oldPath : file.newPath
    }

    private func text(of file: UnifiedPatch.FileChange) -> String {
        (side == .old ? file.reconstructedTexts.old : file.reconstructedTexts.new) ?? ""
    }
}

/// Parsed patches by file, kept as long as the file's modification date is unchanged.
public final class PatchCache: Sendable {
    private let patches = Mutex<[URL: (modified: Date?, patch: UnifiedPatch)]>([:])

    public func patch(at url: URL) async throws -> UnifiedPatch {
        let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        if let cached = patches.withLock({ $0[url] }), cached.modified == modified { return cached.patch }
        let parsed = try await Self.parse(at: url)
        patches.withLock { $0[url] = (modified, parsed) }
        return parsed
    }

    @concurrent
    private static func parse(at url: URL) async throws -> UnifiedPatch {
        UnifiedPatch(parsing: try String(contentsOf: url, encoding: .utf8))
    }
}

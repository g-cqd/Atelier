import AemiRuntime
public import AtelierGit
public import AtelierProcess
public import Foundation

public struct DirectorySource: SourceProvider {
    public let root: URL
    public let runner: any ProcessRunner
    let offload: any BlockingOffload
    let hashFile: SourceLoader.FileHasher
    let hashes: WorkingTreeHashes

    /// Inside a repository, the folder as git sees it: tracked and untracked files, dotfiles included, nothing
    /// git ignores. A tracked file git reports clean takes the blob its index holds, unread: git compares it after
    /// its own conversions (line endings, filters), knows it unchanged when sparse checkout or `skip-worktree` leaves
    /// it off the disk, and knows it whatever its size. Every other file, and every file of a folder outside a
    /// repository, is hashed as it is on disk. Elsewhere, a folder scan that leaves hidden files out. The `stat`
    /// pass, the scan and every hash run on the pool.
    ///
    /// Only the files whose stamp changed since the folder's last listing are read: every other one keeps the blob
    /// id ``WorkingTreeHashes`` holds for it. A file that cannot be hashed, because it vanished, shrank or is not
    /// readable since it was listed, is listed without a blob id, so it counts as changed and is read when shown,
    /// instead of failing the whole folder. A symbolic link is listed with the blob of its target's path, as git
    /// stores it. Inside a repository each file carries its mode, as git would record it, and a submodule is listed
    /// with the commit it has checked out.
    /// - Throws: `CancellationError` when the task is cancelled, even after the last file is hashed: a cancelled
    ///   listing never passes for a finished one, empty or partial.
    @concurrent
    public func entries() async throws -> [GitTreeEntry] {
        guard let view = try await gitView() else {
            return try await hashed(try await Self.scan(root, on: offload), format: nil)
        }
        let clean = view.clean.keys.filter { SourceLoader.isSupported(path: $0) }
        let changed = view.changed.filter { SourceLoader.isSupported(path: $0) }
        async let sizes = Self.sizes(of: clean, under: root, on: offload)
        let hashed = try await hashed(try await Self.stat(changed, under: root, on: offload), format: view.format)
        let known = try await sizes
        let indexed = clean.compactMap { path in
            view.clean[path]
                .map {
                    GitTreeEntry(relativePath: path, blobID: $0.objectID, size: known[path] ?? 0, mode: $0.mode)
                }
        }
        let submodules = try await submoduleEntries(view.submodules)
        return (indexed + hashed + submodules).sorted { $0.relativePath < $1.relativePath }
    }

    /// The submodules, each with the commit it has checked out: the index's commit for one git reports unchanged,
    /// its own `HEAD` for one git reports changed, and the index's again when that cannot be read.
    private func submoduleEntries(_ submodules: [String: (commit: String, isChanged: Bool)]) async throws
        -> [GitTreeEntry]
    {
        var entries: [GitTreeEntry] = []
        for (path, submodule) in submodules.sorted(by: { $0.key < $1.key }) {
            try Task.checkCancellation()
            var commit = submodule.commit
            if submodule.isChanged,
                let head = try? await SourceLoader.git(root.appending(path: path), runner: runner).resolve(ref: "HEAD")
            {
                commit = head
            }
            entries.append(
                GitTreeEntry(relativePath: path, blobID: commit, size: 0, mode: GitTreeEntry.submoduleMode)
            )
        }
        return entries
    }

    /// The listed `files` with their blob ids in `format`, read only for the files whose stamp changed since the
    /// folder's last listing.
    /// - Parameters:
    ///   - files: The files listed, with their stamps.
    ///   - format: The repository's object format; nil for a folder outside every repository, whose files carry no
    ///     mode and hash as SHA-1.
    /// - Returns: An entry per file, without a blob id for one that could not be hashed.
    /// - Throws: `CancellationError` when the task is cancelled.
    private func hashed(_ files: [File], format: ObjectFormat?) async throws -> [GitTreeEntry] {
        let folder = root.standardizedFileURL.path(percentEncoded: false)
        let known = hashes.entries(of: folder)
        var kept: [String: WorkingTreeHashes.Entry] = [:]
        var stale: [File] = []
        for file in files where file.stamp.size <= SourceLoader.maximumHashedSize {
            if let entry = known[file.relativePath], entry.stamp == file.stamp {
                kept[file.relativePath] = entry
            } else {
                stale.append(file)
            }
        }
        let hashed = try await mapConcurrently(stale, limit: SourceLoader.hashingConcurrency) {
            [offload, hashFile] file in
            (file.relativePath, try await offload.run { hashFile(file.fullPath, format ?? .sha1) })
        }
        var fresh: [String: HashedFile] = [:]
        for case (let path, let file?) in hashed {
            fresh[path] = file
            if file.isSettled { kept[path] = WorkingTreeHashes.Entry(stamp: file.stamp, blobID: file.blobID) }
        }
        hashes.store(kept, for: folder)
        try Task.checkCancellation()
        return files.map { file in
            let hashed = fresh[file.relativePath]
            return GitTreeEntry(
                relativePath: file.relativePath,
                blobID: hashed?.blobID ?? kept[file.relativePath]?.blobID,
                size: hashed?.stamp.size ?? file.stamp.size,
                mode: format == nil ? nil : file.mode
            )
        }
    }

    /// What git says of a folder inside a repository, paths relative to the folder: the index entry of every tracked
    /// file whose working-tree file git reports clean, and the paths it reports untracked, conflicted or changed in
    /// the working tree.
    struct GitView {
        let clean: [String: GitIndexEntry]
        let changed: [String]
        /// The submodules, each with the commit the index records and whether git reports it changed.
        let submodules: [String: (commit: String, isChanged: Bool)]
        /// The repository's object format, which a hashed file's id must follow to match a stored one: read from the
        /// index's ids, SHA-1 for an empty index.
        let format: ObjectFormat
    }

    /// The folder as git sees it, through the index and one status; nil for a folder outside every repository.
    private func gitView() async throws -> GitView? {
        guard let repository = await SourceLoader.repositoryRoot(containing: root, runner: runner),
            let prefix = SourceLoader.prefix(of: root, under: repository)
        else { return nil }
        async let index = SourceLoader.git(root, runner: runner).indexEntries()
        async let status = SourceLoader.git(repository, runner: runner).status(includingIgnored: false)
        let changes = SourceLoader.entries(try await status.entries, under: prefix)
        return Self.view(index: try await index, changes: changes)
    }

    /// See ``GitView``: a submodule is on neither file list, but on its own.
    static func view(index: [GitIndexEntry], changes: [GitStatusEntry]) -> GitView {
        let changedSubmodules = Set(changes.filter(\.isSubmodule).map(\.path))
        let changed = Set(
            changes.filter { change in
                !change.isSubmodule
                    && (change.status == .untracked || change.status == .conflicted
                        || change.worktreeStatus != .unmodified)
            }
            .map(\.path)
        )
        var clean: [String: GitIndexEntry] = [:]
        var submodules: [String: (commit: String, isChanged: Bool)] = [:]
        for entry in index where entry.stage == 0 {
            if entry.isSubmodule {
                submodules[entry.path] = (entry.objectID, changedSubmodules.contains(entry.path))
            } else if !changed.contains(entry.path) {
                clean[entry.path] = entry
            }
        }
        let format = index.first.map { ObjectFormat(objectID: $0.objectID) } ?? .sha1
        return GitView(clean: clean, changed: changed.sorted(), submodules: submodules, format: format)
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

    /// The text of the blob the entry was listed with when the repository stores it, which is the file git compares
    /// for a clean file; otherwise the file as it is on disk, a symbolic link's target path for a link.
    public func content(of entry: GitTreeEntry) async throws -> String {
        if let blob = entry.blobID, let git = await gitClient(), let data = try? await git.blobs([blob])[blob] {
            return SourceLoader.text(from: data)
        }
        return SourceLoader.text(from: try await readOnDisk(entry))
    }

    /// Many entries at once: the stored blobs through one `cat-file --batch`, the rest read from disk.
    public func contents(of entries: [GitTreeEntry]) async throws -> [String: String] {
        var stored: [String: Data] = [:]
        if let git = await gitClient() {
            let ids = Array(Set(entries.compactMap(\.blobID)))
            for start in stride(from: 0, to: ids.count, by: SourceLoader.blobBatchSize) {
                let batch = Array(ids[start ..< min(start + SourceLoader.blobBatchSize, ids.count)])
                stored.merge(try await git.blobs(batch)) { first, _ in first }
            }
        }
        let blobs = stored
        let pairs = try await mapConcurrently(entries, limit: SourceLoader.hashingConcurrency) { entry in
            if let data = entry.blobID.flatMap({ blobs[$0] }) {
                return (entry.relativePath, SourceLoader.text(from: data))
            }
            return (entry.relativePath, SourceLoader.text(from: try await readOnDisk(entry)))
        }
        return Dictionary(pairs, uniquingKeysWith: { first, _ in first })
    }

    private func readOnDisk(_ entry: GitTreeEntry) async throws -> Data {
        let path = root.appending(path: entry.relativePath).path(percentEncoded: false)
        return try await offload.run { try SourceLoader.workingTreeContents(atPath: path) }
    }

    private struct File: Sendable {
        let fullPath: String
        let relativePath: String
        let stamp: FileStamp
        /// The mode git would record for the file, from `lstat`; nil from a plain folder scan.
        var mode: String?
    }

    /// Paths `stat`ed per blocking job: one job for most folders, and a cancellation lands between two jobs.
    private static let statBatchSize = 1024

    /// Git run in this folder, when it lies in a repository: `ls-files` then lists paths relative to the folder.
    private func gitClient() async -> GitClient? {
        await SourceLoader.repositoryRoot(containing: root, runner: runner) == nil
            ? nil : SourceLoader.git(root, runner: runner)
    }

    /// ``stat(_:under:)`` on `offload`, in batches of ``statBatchSize`` paths.
    private static func stat(_ paths: [String], under root: URL, on offload: any BlockingOffload) async throws
        -> [File]
    {
        try await batches(of: paths, on: offload) { stat($0, under: root) }.flatMap(\.self)
    }

    /// The sizes of the files at `paths` that exist, a link's being its target path's length; on `offload`.
    private static func sizes(of paths: [String], under root: URL, on offload: any BlockingOffload) async throws
        -> [String: Int]
    {
        let base = basePath(of: root)
        let found = try await batches(of: paths, on: offload) { batch in
            batch.compactMap { path in FileStamp(fileOrLinkAt: base + path).map { (path, $0.size) } }
        }
        return Dictionary(found.flatMap(\.self), uniquingKeysWith: { first, _ in first })
    }

    private static func batches<Result: Sendable>(
        of paths: [String],
        on offload: any BlockingOffload,
        _ work: @escaping @Sendable ([String]) -> Result
    ) async throws -> [Result] {
        let batches = stride(from: 0, to: paths.count, by: statBatchSize)
            .map { Array(paths[$0 ..< min($0 + statBatchSize, paths.count)]) }
        return try await mapConcurrently(batches, limit: 2) { batch in try await offload.run { work(batch) } }
    }

    private static func basePath(of root: URL) -> String {
        let rootPath = root.standardizedFileURL.path(percentEncoded: false)
        return rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
    }

    /// The regular files and symbolic links among `paths`, each with the stamp `lstat` gives it: a path whose file is
    /// gone, a directory (a submodule) or a path git lists that is anything else is left out.
    private static func stat(_ paths: [String], under root: URL) -> [File] {
        let base = basePath(of: root)
        var files: [File] = []
        files.reserveCapacity(paths.count)
        for path in paths {
            let fullPath = base + path
            guard let (stamp, mode) = FileStamp.stampAndMode(fileOrLinkAt: fullPath) else { continue }
            files.append(File(fullPath: fullPath, relativePath: path, stamp: stamp, mode: mode))
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
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .nameKey]
        let base = root.standardizedFileURL
        // Relative URLs: the enumerator hands its entries out under the folder's canonical path (`/private/var` for
        // `/var`), and standardizing each back to the folder's own spelling `stat`s it.
        guard
            let enumerator = FileManager.default.enumerator(
                at: base,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants, .producesRelativePathURLs]
            )
        else {
            throw CocoaError(.fileReadNoSuchFile)
        }

        let basePath = base.path(percentEncoded: false)
        let prefix = basePath.hasSuffix("/") ? basePath : basePath + "/"
        var files: [File] = []
        while let url = enumerator.nextObject() as? URL {
            if cancellation.isRaised { throw CancellationError() }
            let values = try url.resourceValues(forKeys: keys)
            if values.isDirectory == true {
                if SourceLoader.skippedDirectories.contains(values.name ?? "") { enumerator.skipDescendants() }
                continue
            }
            guard values.isRegularFile == true, SourceLoader.isSupported(path: url.lastPathComponent) else { continue }
            let relativePath = url.relativePath
            let fullPath = prefix + relativePath
            guard let stamp = FileStamp(regularFileAt: fullPath) else { continue }
            files.append(File(fullPath: fullPath, relativePath: relativePath, stamp: stamp))
        }
        return files
    }
}

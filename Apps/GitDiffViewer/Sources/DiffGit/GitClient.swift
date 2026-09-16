package import AemiRuntime
import AtelierProcess
import DiffCore
package import Foundation

package enum GitError: Error, LocalizedError {
    case commandFailed(String)
    case notARepository

    package var errorDescription: String? {
        switch self {
            case .commandFailed(let message): message.trimmingCharacters(in: .whitespacesAndNewlines)
            case .notARepository: "Not a git repository"
        }
    }
}

package struct GitClient: Sendable {
    package let repository: URL

    package init(repository: URL) {
        self.repository = repository
    }

    package static func repositoryRoot(containing url: URL) async -> URL? {
        let directory = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        guard let data = try? await run(["rev-parse", "--show-toplevel"], in: directory) else { return nil }
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : URL(filePath: path, directoryHint: .isDirectory)
    }

    package func info() async throws -> RepositoryInfo {
        async let branches = references(pattern: "refs/heads", "refs/remotes")
        async let tags = references(pattern: "refs/tags")
        async let commits = recentCommits(limit: 200)
        return try await RepositoryInfo(root: repository, branches: branches, tags: tags, commits: commits)
    }

    package func resolve(ref: String) async throws -> String {
        let data = try await run(["rev-parse", "--verify", "--quiet", "\(ref)^{commit}"])
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Files of the tree at `ref`, filtered to the supported extensions.
    package func tree(at ref: String, isSupported: @Sendable (String) -> Bool) async throws -> [SourceEntry] {
        Self.parseTree(try await run(["ls-tree", "-r", "-l", "-z", ref]), isSupported: isSupported)
    }

    /// Splits `ls-tree -r -l -z` output: `<mode> blob <id> <size>\t<path>\0` per file; trees and unsupported
    /// paths are left out.
    package static func parseTree(_ data: Data, isSupported: (String) -> Bool) -> [SourceEntry] {
        var entries: [SourceEntry] = []
        for record in data.split(separator: 0) {
            guard let tab = record.firstIndex(of: 9) else { continue }
            let header = String(decoding: record[record.startIndex ..< tab], as: UTF8.self)
            let path = String(decoding: record[record.index(after: tab)...], as: UTF8.self)
            guard isSupported(path) else { continue }
            let fields = header.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count == 4, fields[1] == "blob" else { continue }
            entries.append(SourceEntry(relativePath: path, blobID: String(fields[2]), size: Int(fields[3]) ?? 0))
        }
        return entries
    }

    /// Files of the working tree as git sees it: tracked files plus untracked ones that are not ignored. Index
    /// entries whose file is gone are listed too; the caller drops what it cannot stat.
    package func workingTreePaths() async throws -> [String] {
        Self.parsePaths(try await run(["ls-files", "-z", "--cached", "--others", "--exclude-standard"]))
    }

    /// Untracked files git ignores.
    package func ignoredPaths() async throws -> [String] {
        Self.parsePaths(try await run(["ls-files", "-z", "--others", "--ignored", "--exclude-standard"]))
    }

    /// Splits `ls-files -z` output: one NUL-terminated path per record, in index order.
    package static func parsePaths(_ data: Data) -> [String] {
        data.split(separator: 0, omittingEmptySubsequences: true).map { String(decoding: $0, as: UTF8.self) }
    }

    package func blob(_ id: String) async throws -> Data {
        try await run(["cat-file", "blob", id])
    }

    /// Contents of many blobs through one `cat-file --batch` process instead of one process per blob.
    /// Missing ids are left out of the result.
    package func blobs(_ ids: [String]) async throws -> [String: Data] {
        guard !ids.isEmpty else { return [:] }
        let output = try await run(["cat-file", "--batch"], input: Data((ids.joined(separator: "\n") + "\n").utf8))
        return Self.parseBatch(output)
    }

    /// Splits `cat-file --batch` output: `<id> blob <size>\n<bytes>\n` per object, `<id> missing\n` otherwise.
    package static func parseBatch(_ output: Data) -> [String: Data] {
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

    /// Renames between two refs, or between a ref and the working tree when `to` is nil, old path to new path.
    package func renames(from: String, to: String?) async throws -> [String: String] {
        Self.parseRenames(
            try await run(["diff", "--name-status", "-M", "-z", "--diff-filter=R", from] + (to.map { [$0] } ?? [])))
    }

    /// Splits `diff --name-status -z` output: `R<score>\0<old>\0<new>\0` per rename.
    package static func parseRenames(_ data: Data) -> [String: String] {
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

    private func references(pattern: String...) async throws -> [String] {
        Self.parseReferences(
            try await run(["for-each-ref", "--format=%(refname:short)", "--sort=-committerdate"] + pattern))
    }

    /// One short ref name per line; a remote's `HEAD` pointer is left out because it duplicates a branch.
    package static func parseReferences(_ data: Data) -> [String] {
        String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init).filter { !$0.hasSuffix("/HEAD") }
    }

    private func recentCommits(limit: Int) async throws -> [GitCommit] {
        Self.parseCommits(try await run(["log", "--format=%H%x1f%h%x1f%s", "-n", String(limit)]))
    }

    /// One `<hash>\u{1f}<short hash>\u{1f}<subject>` line per commit; the unit separator keeps subjects with
    /// spaces intact.
    package static func parseCommits(_ data: Data) -> [GitCommit] {
        String(decoding: data, as: UTF8.self).split(separator: "\n")
            .compactMap { line in
                let fields = line.split(separator: "\u{1f}", maxSplits: 2, omittingEmptySubsequences: false)
                guard fields.count == 3 else { return nil }
                return GitCommit(hash: String(fields[0]), shortHash: String(fields[1]), subject: String(fields[2]))
            }
    }

    private func run(_ arguments: [String], input: Data? = nil) async throws -> Data {
        try await Self.run(arguments, input: input, in: repository)
    }

    /// Where git lives: `GDV_GIT` when it names an executable, else the first `git` on `PATH` or in the usual
    /// toolchain locations, `/usr/bin/git` last because that one is a shim that re-resolves the developer directory
    /// on every launch.
    package static let executable: URL = ExecutableResolver(
        overrideVariable: "GDV_GIT",
        searchPaths: [
            "/Applications/Xcode.app/Contents/Developer/usr/bin", "/Library/Developer/CommandLineTools/usr/bin",
            "/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin"
        ],
        excludedPaths: ["/usr/bin"]
    )
    .resolve("git")

    /// Threads for the blocking parts of a git run. Four is enough for the batch reads a large selection runs side
    /// by side; further runs queue behind them rather than spawning a thread each.
    package static let blockingPool = BlockingOffloadPool(width: 4)
    private static let runner = HardenedProcessRunner(pool: blockingPool)

    /// Runs git and returns its standard output; a non-zero exit becomes a ``GitError`` carrying its standard error,
    /// and cancelling the task terminates git.
    private static func run(_ arguments: [String], input: Data? = nil, in directory: URL) async throws -> Data {
        PhaseTrace.log("git \(arguments.prefix(2).joined(separator: " "))")
        defer { PhaseTrace.log("git done \(arguments.prefix(2).joined(separator: " "))") }
        let spec = ProcessSpec(
            executable: executable, arguments: arguments, currentDirectory: directory, standardInput: input)
        let output = try await runner.run(spec)
        guard output.succeeded else { throw GitError.commandFailed(output.errorText) }
        return output.standardOutput
    }
}

extension GitCommit {
    /// The short form of a full SHA-1 or SHA-256 hash, for labels; anything else is shown as typed.
    package static func abbreviated(_ ref: String) -> String {
        guard ref.count == 40 || ref.count == 64, ref.allSatisfy(\.isHexDigit) else { return ref }
        return String(ref.prefix(7))
    }
}

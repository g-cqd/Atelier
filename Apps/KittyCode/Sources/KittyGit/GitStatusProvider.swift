// Predates the size and complexity gates; reviewed opt-out tracked in g-cqd/Atelier#1.
// swiftlint:disable type_body_length
public import AtelierProcess
import Foundation
public import KittyFileTree
import Synchronization
import System

import struct AtelierGit.GitClient

public final class GitStatusProvider: FileStatusProvider, GitLineDecorationProvider,
    @unchecked Sendable
{
    private enum BaseContent: Sendable {
        case missing
        case text(String)
    }

    private struct State: Sendable {
        var statuses: [String: FileStatus] = [:]
        var branch: String?
        var summary: FileStatusSummary = FileStatusSummary()
        var baseContents: [String: BaseContent] = [:]
    }

    private let rootPath: String
    private let runner: any ProcessRunner
    private let lock: Mutex<State>
    private let inFlightLock = Mutex([String: Task<BaseContent, Never>]())

    /// - Parameters:
    ///   - rootPath: The repository root every git invocation runs in.
    ///   - runner: How `git` is spawned; the app owns the pool behind it, tests inject a fake.
    public init(rootPath: String, runner: any ProcessRunner) {
        self.rootPath = Self.normalizePath(rootPath)
        self.runner = runner
        self.lock = Mutex(State())
    }

    public func status(for path: String) -> FileStatus? {
        let normalizedPath = Self.normalizePath(path)
        return lock.withLock { state in
            state.statuses[normalizedPath]
        }
    }

    public var branchName: String? {
        lock.withLock { $0.branch }
    }

    public var summary: FileStatusSummary {
        lock.withLock { $0.summary }
    }

    public func refresh() async {
        let branch = await readBranch()
        let (statuses, summary) = await readStatuses()
        lock.withLock { state in
            state.branch = branch
            state.statuses = statuses
            state.summary = summary
            state.baseContents.removeAll(keepingCapacity: true)
        }
    }

    public func lineDecorations(for path: String, lines: [String]) async -> GitLineDecorations {
        let normalizedPath = Self.normalizePath(path)
        let status = status(for: normalizedPath)

        if lines.isEmpty {
            return .empty
        }

        if status == .untracked {
            return Self.addedLineDecorations(for: lines, color: .untracked)
        }

        guard let relativePath = relativePath(for: normalizedPath) else {
            return .empty
        }

        let baseContent = await readBaseContent(for: normalizedPath, relativePath: relativePath)
        switch baseContent {
            case .missing:
                guard status == .added else {
                    return .empty
                }
                return Self.addedLineDecorations(for: lines, color: .added)
            case .text(let content):
                let addedColor: FileStatusColor = status == .untracked ? .untracked : .added
                let baseLines = Self.splitLines(content)
                return makeLineDecorations(
                    baseLines: baseLines, currentLines: lines, addedColor: addedColor)
        }
    }

    // MARK: - Git commands

    private func readBranch() async -> String? {
        let output = await runGit(arguments: ["branch", "--show-current"])
        let trimmed = output?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }

    private func readStatuses() async -> ([String: FileStatus], FileStatusSummary) {
        guard let output = await runGit(arguments: ["status", "--porcelain=v1"]) else {
            return ([:], FileStatusSummary())
        }
        return parseGitStatus(output, rootPath: rootPath)
    }

    private func runGit(arguments: [String]) async -> String? {
        await Self.runGit(arguments: arguments, workingDirectory: rootPath, runner: runner)
    }

    private func readBaseContent(for normalizedPath: String, relativePath: String) async
        -> BaseContent
    {
        if let cached = lock.withLock({ $0.baseContents[normalizedPath] }) {
            return cached
        }

        let task: Task<BaseContent, Never> = inFlightLock.withLock { inFlight in
            if let existing = inFlight[normalizedPath] {
                return existing
            }
            let newTask = Task<BaseContent, Never> {
                await loadBaseContent(relativePath: relativePath)
            }
            inFlight[normalizedPath] = newTask
            return newTask
        }

        let content = await task.value
        lock.withLock { $0.baseContents[normalizedPath] = content }
        inFlightLock.withLock { $0[normalizedPath] = nil }
        return content
    }

    private func loadBaseContent(relativePath: String) async -> BaseContent {
        guard let output = await runGit(arguments: ["show", "HEAD:\(relativePath)"]) else {
            return .missing
        }
        return .text(output)
    }

    // MARK: - Parsing

    func parseGitStatus(_ output: String, rootPath: String) -> (
        [String: FileStatus], FileStatusSummary
    ) {
        var statuses: [String: FileStatus] = [:]
        var summary = FileStatusSummary()
        let normalizedRoot = Self.normalizePath(rootPath)
        let root = normalizedRoot.hasSuffix("/") ? normalizedRoot : normalizedRoot + "/"

        for line in output.split(separator: "\n", omittingEmptySubsequences: true) where line.count >= 4 {
            let index = line.index(line.startIndex, offsetBy: 0)
            let worktree = line.index(line.startIndex, offsetBy: 1)
            let pathStart = line.index(line.startIndex, offsetBy: 3)
            let x = line[index]
            let y = line[worktree]
            var relativePath = String(line[pathStart...])

            // Handle renamed files: "R  old -> new"
            if let arrowRange = relativePath.range(of: " -> ") {
                relativePath = String(relativePath[arrowRange.upperBound...])
            }

            let absolutePath = Self.normalizePath(root + relativePath)
            let status = mapStatus(x: x, y: y)
            statuses[absolutePath] = status

            switch status {
                case .modified, .renamed: summary.modified += 1
                case .added: summary.added += 1
                case .untracked: summary.untracked += 1
                case .deleted: summary.deleted += 1
                case .conflicted: summary.conflicted += 1
                case .ignored, .clean: break
            }

            // Propagate status to parent directories
            propagateToParents(absolutePath, status: status, root: root, into: &statuses)
        }

        return (statuses, summary)
    }

    private func mapStatus(x: Character, y: Character) -> FileStatus {
        // Conflicts
        if (x == "U" || y == "U") || (x == "A" && y == "A") || (x == "D" && y == "D") {
            return .conflicted
        }
        // Untracked
        if x == "?" && y == "?" {
            return .untracked
        }
        // Ignored
        if x == "!" && y == "!" {
            return .ignored
        }
        // Renamed
        if x == "R" {
            return .renamed
        }
        // Added
        if x == "A" && y != "M" {
            return .added
        }
        // Deleted
        if x == "D" || y == "D" {
            return .deleted
        }
        // Modified (any other change)
        return .modified
    }

    private func propagateToParents(
        _ path: String, status: FileStatus, root: String, into statuses: inout [String: FileStatus]
    ) {
        var current = FilePath(path).removingLastComponent().string
        while current.hasPrefix(root) || current + "/" == root {
            if current.count < root.count { break }
            if let existing = statuses[current] {
                if severity(of: status) > severity(of: existing) {
                    statuses[current] = status
                }
            } else {
                statuses[current] = status
            }
            let parent = FilePath(current).removingLastComponent().string
            if parent == current { break }
            current = parent
        }
    }

    private func severity(of status: FileStatus) -> Int {
        switch status {
            case .conflicted: return 5
            case .deleted: return 4
            case .modified, .renamed: return 3
            case .added: return 2
            case .untracked: return 1
            case .ignored, .clean: return 0
        }
    }

    private func relativePath(for normalizedPath: String) -> String? {
        guard normalizedPath != rootPath else { return nil }

        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard normalizedPath.hasPrefix(rootPrefix) else {
            return nil
        }

        return String(normalizedPath.dropFirst(rootPrefix.count))
    }

    // MARK: - Repository detection

    public static func isGitRepository(_ path: String, runner: any ProcessRunner) async -> Bool {
        await repositoryRoot(for: path, runner: runner) != nil
    }

    public static func repositoryRoot(for path: String, runner: any ProcessRunner) async -> String? {
        let raw = await runGit(
            arguments: ["-C", path, "rev-parse", "--show-toplevel"], runner: runner)
        let root = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !root.isEmpty else { return nil }
        return normalizePath(root)
    }

    private static func normalizePath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    static func splitLines(_ content: String) -> [String] {
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
            .map(
                String.init)
        return lines.isEmpty ? [""] : lines
    }

    static func addedLineDecorations(for lines: [String], color: FileStatusColor)
        -> GitLineDecorations
    {
        guard !lines.isEmpty else { return .empty }
        return GitLineDecorations(
            markers: Dictionary(uniqueKeysWithValues: lines.indices.map { ($0, color) })
        )
    }

    func makeLineDecorations(
        baseLines: [String],
        currentLines: [String],
        addedColor: FileStatusColor
    ) -> GitLineDecorations {
        guard !currentLines.isEmpty else {
            return .empty
        }

        let difference = currentLines.difference(from: baseLines)
        let removalOffsets = difference.removals
            .compactMap { change -> Int? in
                if case .remove(let offset, _, _) = change { return offset }
                return nil
            }
            .sorted()
        let insertionOffsets = difference.insertions
            .compactMap { change -> Int? in
                if case .insert(let offset, _, _) = change { return offset }
                return nil
            }
            .sorted()

        if removalOffsets.isEmpty, insertionOffsets.isEmpty {
            return .empty
        }

        var markers: [Int: FileStatusColor] = [:]
        var baseIndex = 0
        var currentIndex = 0
        var removalIndex = 0
        var insertionIndex = 0

        while baseIndex < baseLines.count || currentIndex < currentLines.count {
            let removalCount = Self.consumeConsecutiveOffsets(
                removalOffsets,
                index: &removalIndex,
                startingAt: baseIndex
            )
            let insertionCount = Self.consumeConsecutiveOffsets(
                insertionOffsets,
                index: &insertionIndex,
                startingAt: currentIndex
            )

            if removalCount == 0, insertionCount == 0 {
                if baseIndex < baseLines.count {
                    baseIndex += 1
                }
                if currentIndex < currentLines.count {
                    currentIndex += 1
                }
                continue
            }

            let modifiedCount = min(removalCount, insertionCount)
            for offset in 0 ..< modifiedCount {
                markers[currentIndex + offset] = .modified
            }

            if insertionCount > modifiedCount {
                for offset in modifiedCount ..< insertionCount {
                    Self.mergeMarker(addedColor, into: &markers, at: currentIndex + offset)
                }
            }

            if removalCount > insertionCount {
                let anchor = min(currentIndex + modifiedCount, max(0, currentLines.count - 1))
                Self.mergeMarker(.deleted, into: &markers, at: anchor)
            }

            baseIndex += removalCount
            currentIndex += insertionCount
        }

        return GitLineDecorations(markers: markers)
    }

    private static func consumeConsecutiveOffsets(
        _ offsets: [Int],
        index: inout Int,
        startingAt start: Int
    ) -> Int {
        guard index < offsets.count, offsets[index] == start else {
            return 0
        }

        var count = 0
        var expected = start
        while index < offsets.count, offsets[index] == expected {
            count += 1
            index += 1
            expected += 1
        }
        return count
    }

    private static func mergeMarker(
        _ incoming: FileStatusColor,
        into markers: inout [Int: FileStatusColor],
        at index: Int
    ) {
        if let existing = markers[index] {
            if markerPriority(of: incoming) > markerPriority(of: existing) {
                markers[index] = incoming
            }
        } else {
            markers[index] = incoming
        }
    }

    private static func markerPriority(of color: FileStatusColor) -> Int {
        switch color {
            case .deleted: return 4
            case .modified: return 3
            case .added: return 2
            case .untracked: return 1
            case .conflicted: return 5
            case .clean: return 0
        }
    }

    /// Default deadline for any single git invocation. A hung `git` should never
    /// freeze the editor — after this duration we send `SIGTERM` and return `nil`.
    fileprivate static let defaultGitTimeout: Duration = .seconds(10)

    /// Runs `git` asynchronously without blocking the executor thread.
    ///
    /// Uses `terminationHandler` to resume after the process exits and reads the
    /// captured stdout via `FileHandle.readToEnd()` only after EOF is guaranteed.
    /// Falls back to `nil` and terminates the child process if it exceeds
    /// `timeout`.
    /// Minimal scrubbed environment for `git` invocations. Audit F9/NF6 —
    /// the parent process's full environment used to be inherited:
    /// `GIT_DIR`, `GIT_SSH_COMMAND`, `GIT_CONFIG_*`, `LD_*`, `PATH`,
    /// `SSH_*` were all attacker-influenceable. Combined with workspace-
    /// controlled `.git/config`, opening a hostile repo was an RCE class
    /// (CVE-2024-32002, -32004 et al). The whitelist here pins git to:
    ///   * a fixed `PATH` (no `~/bin/git` shadow)
    ///   * `LANG`/`LC_ALL = C` (stable output parsing)
    ///   * `HOME` (legitimately needed for `~/.gitconfig`)
    ///   * `GIT_OPTIONAL_LOCKS=0` (no lockfile races)
    ///   * `GIT_TERMINAL_PROMPT=0` (no credential prompt blocking)
    ///   * `GIT_CONFIG_NOSYSTEM=1` (skip `/etc/gitconfig` which a
    ///     shared-host attacker could control)
    /// Every callsite ALSO passes hardening `-c` flags to refuse the
    /// known-exploited config keys at invocation time.
    private static var scrubbedEnvironment: [String: String] {
        [
            "PATH": "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin",
            "LANG": "C",
            "LC_ALL": "C",
            "HOME": NSHomeDirectory(),
            "GIT_OPTIONAL_LOCKS": "0",
            "GIT_TERMINAL_PROMPT": "0",
            "GIT_CONFIG_NOSYSTEM": "1"
        ]
    }

    /// `-c key=value` flags applied to every git invocation. These
    /// disable the config knobs Git CVE writeups have flagged as
    /// remote-code-execution vectors when the workspace's `.git/config`
    /// is attacker-controlled. Bypassable only by changing the source —
    /// no workspace knob can re-enable them.
    private static let gitHardeningFlags: [String] = [
        "-c", "protocol.file.allow=user",
        "-c", "core.fsmonitor=false",
        "-c", "core.sshCommand=/usr/bin/false",
        "-c", "core.hooksPath=/dev/null"
    ]

    /// Runs `git` through the injected runner and returns its trimmed standard output, or nil on
    /// a non-zero exit, a launch failure, a timeout, or cancellation — the runner owns
    /// terminating the child in every one of those cases, so there is no watchdog here.
    fileprivate static func runGit(
        arguments: [String],
        workingDirectory: String? = nil,
        runner: any ProcessRunner,
        timeout: Duration = defaultGitTimeout
    ) async -> String? {
        let environment = scrubbedEnvironment.merging(GitClient.hardeningEnvironment) { current, _ in current }
        let spec = ProcessSpec(
            executable: GitClient.executable,
            arguments: gitHardeningFlags + arguments,
            currentDirectory: workingDirectory.map { URL(fileURLWithPath: $0) },
            environment: .exactly(environment),
            timeout: timeout
        )
        guard let output = try? await runner.run(spec), output.succeeded else { return nil }
        return String(data: output.standardOutput, encoding: .utf8)
    }
}

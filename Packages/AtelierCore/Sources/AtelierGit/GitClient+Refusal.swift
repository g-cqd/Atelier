public import AtelierProcess
public import Foundation

/// A repository whose own configuration ``GitConfigPolicy`` refuses: where it is, and which keys it refuses.
public struct GitConfigRefusal: Sendable, Hashable {
    /// The repository's working-tree root: the nearest directory holding a `.git` entry.
    public let root: URL
    /// The refused keys, in the order git listed them, without their values.
    public let keys: [String]

    public init(root: URL, keys: [String]) {
        self.root = root
        self.keys = keys
    }

    /// The keys the user may allow in this repository (``GitConfigPolicy/canBeAllowed(_:)``).
    public var allowableKeys: [String] { keys.filter(GitConfigPolicy.canBeAllowed) }

    /// The keys that name a program, which no allowance re-admits.
    public var blockingKeys: [String] { keys.filter { !GitConfigPolicy.canBeAllowed($0) } }
}

extension GitClient {
    /// The refusal of the repository `url` lies in; nil when `url` lies in no repository, when its configuration is
    /// approved, or when git fails for another reason. The root is found from the `.git` entry without running git,
    /// since no git command runs in a refused repository.
    public static func configurationRefusal(
        containing url: URL,
        runner: any ProcessRunner,
        timeout: Duration? = nil,
        isolation: GitIsolation = .strict,
        gate: GitConfigGate = .shared
    ) async -> GitConfigRefusal? {
        guard let root = enclosingRepositoryRoot(of: url) else { return nil }
        do {
            _ = try await approvedConfiguration(
                in: root,
                runner: runner,
                timeout: timeout,
                isolation: isolation,
                gate: gate
            )
            return nil
        } catch GitError.refusedConfiguration(let keys) {
            return GitConfigRefusal(root: root, keys: keys)
        } catch {
            return nil
        }
    }

    /// The nearest directory at or above `url` that holds a `.git` entry, a folder or a linked worktree's file.
    static func enclosingRepositoryRoot(of url: URL) -> URL? {
        var directory = (url.hasDirectoryPath ? url : url.deletingLastPathComponent()).standardizedFileURL
        while true {
            if FileManager.default.fileExists(atPath: directory.appending(path: ".git").path(percentEncoded: false)) {
                return directory
            }
            let parent = directory.deletingLastPathComponent()
            guard parent.path(percentEncoded: false) != directory.path(percentEncoded: false) else { return nil }
            directory = parent
        }
    }
}

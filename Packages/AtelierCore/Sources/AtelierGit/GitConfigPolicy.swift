import Darwin
public import Foundation
import Synchronization

/// Where `git config --show-scope` says an entry came from.
public enum GitConfigScope: String, Sendable, Hashable, CaseIterable {
    case system
    case global
    case local
    case worktree
    case command
    /// A file git reports without a scope of its own, such as Xcode's `share/git-core/gitconfig`.
    case unknown

    /// True for the two scopes the repository itself owns: `.git/config` and `.git/config.worktree`, with whatever
    /// their `include` directives pulled in. These are the entries an unpacked or shared repository controls.
    public var isRepositoryOwned: Bool { self == .local || self == .worktree }
}

/// One entry of `git config --list -z --includes --show-scope --show-origin`.
public struct GitConfigEntry: Sendable, Hashable {
    public let scope: GitConfigScope
    /// The file git read the entry from, absolute; nil when the origin is not a file.
    public let file: String?
    /// The key as git prints it: section and last component lower-cased, subsection as written.
    public let key: String
    /// nil for a key written with no value at all, which git prints without its newline.
    public let value: String?

    public init(scope: GitConfigScope, file: String?, key: String, value: String?) {
        self.scope = scope
        self.file = file
        self.key = key
        self.value = value
    }
}

/// What the policy decided about one repository's own configuration, and the values later commands need from it.
public struct GitConfigVerdict: Sendable, Hashable {
    /// Every repository-owned key the policy refuses, in the order git listed them, without their values. Empty for
    /// an approved repository.
    public let refusedKeys: [String]
    /// Filter driver names defined in the repository's own scopes, for the flags that blank them.
    public let filterDrivers: [String]
    /// The repository-owned entries, for the remote URL and refspecs a fetch needs.
    public let entries: [GitConfigEntry]
    /// Generic `credential.helper` values defined outside the repository, in the order git listed them. The fetch
    /// pins reset the helper list to drop anything the repository added; these are put back, so the user's own
    /// keychain helper still answers for a private `https` remote.
    public let userCredentialHelpers: [String]
    /// The files the verdict was read from, for the cache that keys on their modification dates.
    public let files: [String]

    public var isApproved: Bool { refusedKeys.isEmpty }

    /// The first value of `key` among the repository-owned entries.
    public func value(forKey key: String) -> String? {
        entries.first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value
    }

    /// Every value of `key` among the repository-owned entries, in order; a multi-valued key such as
    /// `remote.<name>.fetch` keeps each line.
    public func values(forKey key: String) -> [String] {
        entries.filter { $0.key.caseInsensitiveCompare(key) == .orderedSame }.compactMap(\.value)
    }
}

/// Which repository-owned configuration keys are inert, and which values a fetch may act on.
///
/// A repository carries its own `.git/config`, and git runs the commands that configuration names: a `filter`
/// driver during `status` and `diff`, `gpg.program` during `log`, a transport helper or credential helper during
/// `fetch`. Reading the configuration executes nothing, so ``GitClient`` reads it first and refuses to run git at
/// all when a key falls outside this allowlist. The allowlist is the decision; ``namesAProgram(_:)`` is a floor
/// under it, so widening the allowlist cannot accidentally re-admit a key that runs something.
public enum GitConfigPolicy {
    /// The read that decides the verdict. It executes nothing: the verifier ran it with `core.fsmonitor` set and no
    /// program started. `--includes` resolves `include.path` so an included file's keys are judged too, and git
    /// reports them under the scope of the file that included them.
    public static let listingArguments = [
        "config", "--list", "-z", "--includes", "--show-scope", "--show-origin"
    ]

    /// Splits the listing into entries: three NUL-terminated fields each, `<scope>`, `<origin>`, `<key>\n<value>`.
    /// A value may itself contain newlines, so only the first one separates key from value.
    /// - Parameters:
    ///   - data: git's standard output for ``listingArguments``.
    ///   - directory: The working directory of the run, which git prints local origins relative to.
    /// - Returns: nil when the field count is not a multiple of three, which means the output was truncated.
    /// - Complexity: O(output)
    public static func entries(inListing data: Data, relativeTo directory: URL) -> [GitConfigEntry]? {
        var fields = data.split(separator: 0, omittingEmptySubsequences: false)
        if fields.last?.isEmpty == true { fields.removeLast() }
        guard fields.count % 3 == 0 else { return nil }
        var entries: [GitConfigEntry] = []
        entries.reserveCapacity(fields.count / 3)
        for index in stride(from: 0, to: fields.count, by: 3) {
            let scope = GitConfigScope(rawValue: String(decoding: fields[index], as: UTF8.self)) ?? .unknown
            let origin = String(decoding: fields[index + 1], as: UTF8.self)
            let pair = String(decoding: fields[index + 2], as: UTF8.self)
            let separator = pair.firstIndex(of: "\n")
            entries.append(
                GitConfigEntry(
                    scope: scope, file: Self.file(fromOrigin: origin, relativeTo: directory),
                    key: separator.map { String(pair[..<$0]) } ?? pair,
                    value: separator.map { String(pair[pair.index(after: $0)...]) }))
        }
        return entries
    }

    /// The verdict on `entries`: every repository-owned key is judged, and the values other commands need are kept.
    /// - Complexity: O(entries)
    public static func verdict(for entries: [GitConfigEntry]) -> GitConfigVerdict {
        var refused: [String] = []
        var drivers: [String] = []
        var owned: [GitConfigEntry] = []
        var helpers: [String] = []
        var files: Set<String> = []
        for entry in entries {
            guard entry.scope.isRepositoryOwned else {
                if entry.key.caseInsensitiveCompare("credential.helper") == .orderedSame, let value = entry.value {
                    helpers.append(value)
                }
                continue
            }
            owned.append(entry)
            if let file = entry.file { files.insert(file) }
            let parts = Parts(entry.key)
            if parts.section == "filter", let driver = parts.subsection, !drivers.contains(driver) {
                drivers.append(driver)
            }
            if !isInert(parts) { refused.append(entry.key) }
        }
        return GitConfigVerdict(
            refusedKeys: refused, filterDrivers: drivers, entries: owned, userCredentialHelpers: helpers,
            files: files.sorted())
    }

    /// True when a repository may hold `key` without git running anything the repository chose.
    public static func isInert(_ key: String) -> Bool {
        isInert(Parts(key))
    }

    /// `-c` flags that blank every filter driver the repository defines, so neither the clean, the smudge nor the
    /// long-running process filter can start even if one of these keys reaches a command. `required=false` keeps git
    /// from failing the command once the driver is empty.
    public static func filterBlankingFlags(for drivers: [String]) -> [String] {
        drivers.flatMap { driver in
            ["clean", "smudge", "process"].flatMap { ["-c", "filter.\(driver).\($0)="] }
                + ["-c", "filter.\(driver).required=false"]
        }
    }

    // MARK: - Transports

    /// `url` when a fetch may reach it: an `https://` or `ssh://` URL, or the scp-like `[user@]host:path` form that
    /// every `git@host:path` remote uses. A local path, a `git://`, `http://` or `file://` URL and a transport
    /// helper such as `ext::sh -c …` are all refused, since the first three carry no authentication the user
    /// expects and the last one is a command.
    /// - Returns: nil when the URL is not one a fetch may reach.
    public static func transportURL(_ url: String) -> String? {
        guard !url.isEmpty, !url.hasPrefix("-"), !url.utf8.contains(0), !url.utf8.contains(0x0A) else { return nil }
        guard !hasTransportHelperPrefix(url) else { return nil }
        if let schemeEnd = url.range(of: "://") {
            let scheme = url[..<schemeEnd.lowerBound].lowercased()
            guard scheme == "https" || scheme == "ssh" else { return nil }
            let authority = url[schemeEnd.upperBound...].prefix { $0 != "/" }
            return hasUsableHost(authority) ? url : nil
        }
        // scp-like: everything before the first colon is the host, and a colon after a slash is part of a path.
        guard let colon = url.firstIndex(of: ":") else { return nil }
        let authority = url[..<colon]
        guard !authority.contains("/"), hasUsableHost(authority) else { return nil }
        return url
    }

    /// `url` with any user information removed, for an error message that must name the remote without carrying the
    /// token or password a URL can hold.
    public static func redacted(_ url: String) -> String {
        guard let at = url.lastIndex(of: "@") else { return url }
        let afterUserInformation = url.index(after: at)
        if let schemeEnd = url.range(of: "://") {
            return url.replacingCharacters(in: schemeEnd.upperBound ..< afterUserInformation, with: "")
        }
        return String(url[afterUserInformation...])
    }

    /// True when neither the user information nor the host of `authority` could be read as an option by `ssh`, and
    /// the host is there at all.
    private static func hasUsableHost(_ authority: Substring) -> Bool {
        guard !authority.hasPrefix("-") else { return false }
        let host = authority.lastIndex(of: "@").map { authority[authority.index(after: $0)...] } ?? authority
        return !host.isEmpty && !host.hasPrefix("-")
    }

    /// True for git's `<helper>::<address>` form, which names a program to speak the transport.
    private static func hasTransportHelperPrefix(_ url: String) -> Bool {
        guard let colon = url.firstIndex(of: ":"), url[colon...].hasPrefix("::") else { return false }
        let helper = url[..<colon]
        return !helper.isEmpty
            && helper.allSatisfy { $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." }
    }

    // MARK: - The allowlist

    /// A key split the way git reads it: `<section>.<subsection>.<leaf>`, where the subsection may itself hold dots
    /// and keeps its case, and a two-part key has no subsection.
    private struct Parts {
        let section: String
        let subsection: String?
        let leaf: String

        init(_ key: String) {
            guard let first = key.firstIndex(of: "."), let last = key.lastIndex(of: ".") else {
                section = key.lowercased()
                subsection = nil
                leaf = ""
                return
            }
            section = key[..<first].lowercased()
            leaf = key[key.index(after: last)...].lowercased()
            subsection = first == last ? nil : String(key[key.index(after: first) ..< last])
        }
    }

    private static func isInert(_ parts: Parts) -> Bool {
        // A key git printed always has a section and a leaf; anything else is not a key this policy can judge.
        guard !parts.leaf.isEmpty, !namesAProgram(parts) else { return false }
        if inertSections.contains(parts.section) { return true }
        if inertLeaves[parts.section]?.contains(parts.leaf) == true { return true }
        return parts.subsection == nil && pinnedKeys.contains("\(parts.section).\(parts.leaf)")
    }

    /// The keys the security review and the verifier name as ways for a repository to choose a command. A key
    /// outside the allowlist is refused anyway; this floor is what keeps a later, wider allowlist from re-admitting
    /// one of them. `url.*` is here because a `url."ext::…".insteadOf` rewrite turns a fetch by explicit `https`
    /// URL back into a transport helper.
    private static func namesAProgram(_ parts: Parts) -> Bool {
        switch parts.section {
            case "filter", "credential", "protocol", "url": true
            case "include", "includeif": true
            case "diff": parts.leaf == "command" || parts.leaf == "textconv" || parts.leaf == "external"
            case "gpg": parts.leaf.hasSuffix("program") || parts.leaf == "defaultkeycommand"
            case "log": parts.leaf == "showsignature"
            case "core":
                ["askpass", "gitproxy", "worktree", "alternaterefscommand", "excludesfile", "attributesfile"]
                    .contains(parts.leaf)
            case "remote": ["uploadpack", "receivepack", "vcs", "proxy"].contains(parts.leaf)
            case "submodule": parts.leaf == "update"
            default: false
        }
    }

    /// Sections where no documented key names a program. A repository may hold any leaf here: third-party tools
    /// invent their own (`branch.<name>.github-pr-owner-number`, `branch.<name>.vscode-merge-base`), and refusing
    /// those would refuse ordinary checkouts.
    private static let inertSections: Set<String> = [
        "advice", "am", "apply", "blame", "branch", "checkout", "clean", "color", "column", "commit", "extensions",
        "fetch", "format", "grep", "index", "log", "mailmap", "pack", "pretty", "pull", "push", "rebase", "rerere",
        "revert", "stash", "status", "tag", "transfer", "user", "versionsort", "worktree"
    ]

    /// Sections that hold both inert leaves and leaves the apps must never act on.
    private static let inertLeaves: [String: Set<String>] = [
        "core": [
            "repositoryformatversion", "filemode", "bare", "logallrefupdates", "ignorecase", "precomposeunicode",
            "symlinks", "autocrlf", "eol", "safecrlf", "quotepath", "trustctime", "checkstat", "sharedrepository",
            "compression", "loosecompression", "bigfilethreshold", "packedgitlimit", "packedgitwindowsize",
            "deltabasecachelimit", "preloadindex", "untrackedcache", "commitgraph", "multipackindex",
            "sparsecheckout", "sparsecheckoutcone", "splitindex", "protecthfs", "protectntfs", "longpaths",
            "abbrev", "whitespace", "usereplacerefs", "logpackaccess", "fsync", "fsyncmethod", "fsyncobjectfiles"
        ],
        "remote": [
            "url", "pushurl", "fetch", "push", "mirror", "tagopt", "prune", "prunetags", "partialclonefilter",
            "promisor", "serveroption", "followremotehead", "negotiationrestrict", "gh-resolved"
        ],
        "diff": [
            "algorithm", "renames", "renamelimit", "indentheuristic", "mnemonicprefix", "noprefix", "colormoved",
            "colormovedws", "context", "interhunkcontext", "submodule", "orderfile", "wserrorhighlight",
            "ignoresubmodules", "autorefreshindex", "dirstat", "relative", "statgraphwidth", "suppressblankempty"
        ],
        // `git submodule sync` and `git init` write these into a repository's own configuration.
        "submodule": [
            "url", "path", "active", "branch", "ignore", "shallow", "fetchjobs", "recurse", "fetchrecursesubmodules"
        ],
        "init": ["defaultbranch", "defaultobjectformat", "defaultrefformat"]
    ]

    /// Every key ``GitIsolation`` pins on the command line, where the command line wins over `.git/config`. A
    /// repository may hold one: the pin makes it inert, which is why `core.hooksPath` checkouts (husky, `.githooks`)
    /// still open. A key that also appears in ``namesAProgram(_:)``, such as `gpg.program`, stays refused.
    private static let pinnedKeys: Set<String> = {
        let flags = GitIsolation.strictConfigurationFlags + GitIsolation.networkingConfigurationFlags
        return Set(
            flags.compactMap { flag in
                guard let equals = flag.firstIndex(of: "=") else { return nil }
                return String(flag[..<equals]).lowercased()
            })
    }()

    /// The absolute path an origin names, or nil when the origin is not a file. Git prints a repository's own files
    /// relative to the working directory of the run.
    private static func file(fromOrigin origin: String, relativeTo directory: URL) -> String? {
        guard origin.hasPrefix("file:") else { return nil }
        let path = String(origin.dropFirst("file:".count))
        guard !path.isEmpty else { return nil }
        guard !path.hasPrefix("/") else { return path }
        return directory.appending(path: path, directoryHint: .notDirectory).path(percentEncoded: false)
    }
}

/// The configuration gate in front of every git run, with the verdict cached per directory.
///
/// The read costs a git process, and GitDiffViewer runs `git status` on every load and every index change, so a
/// verdict is kept until one of the files it was read from changes. The check is the file's device, inode, size and
/// modification time, plus the modification time of the directory holding it, so a configuration file that is
/// created, replaced by rename or edited in place all invalidate the entry.
public final class GitConfigGate: Sendable {
    /// The gate every ``GitClient`` uses unless a test injects its own.
    public static let shared = GitConfigGate()

    /// One cached repository. The isolation is part of the key because it decides which files git reads: a strict
    /// run sets `GIT_CONFIG_NOSYSTEM`, so its listing has no system-scope entries and no user credential helper.
    private struct Key: Hashable, Sendable {
        let path: String
        let isolation: GitIsolation
    }

    private struct Entry: Sendable {
        let verdict: GitConfigVerdict
        let stamps: [GitFileStamp]
    }

    private struct Storage: Sendable {
        var entries: [Key: Entry] = [:]
        var order: [Key] = []
    }

    /// How many repositories keep a cached verdict; the least recently read one is dropped beyond it.
    public let capacity: Int
    private let storage = Mutex(Storage())

    public init(capacity: Int = 32) {
        self.capacity = max(1, capacity)
    }

    /// The verdict for the repository at `directory`, from the cache when every file it was read from is unchanged,
    /// otherwise from `read`.
    /// - Parameters:
    ///   - directory: The repository the verdict is about, and the working directory the listing is read in.
    ///   - isolation: The isolation the listing is read under; part of the cache key.
    ///   - read: Runs ``GitConfigPolicy/listingArguments`` and returns git's standard output.
    /// - Returns: The verdict, refusing the repository when git's output could not be read at all.
    /// - Throws: Whatever `read` throws.
    /// - Complexity: O(files) `stat` calls on a hit; one git process on a miss.
    public func verdict(
        in directory: URL, isolation: GitIsolation, reading read: @Sendable () async throws -> Data
    ) async rethrows -> GitConfigVerdict {
        let key = Key(path: directory.path(percentEncoded: false), isolation: isolation)
        if let cached = cachedVerdict(forKey: key) { return cached }
        let data = try await read()
        guard let entries = GitConfigPolicy.entries(inListing: data, relativeTo: directory) else {
            // Truncated output: nothing can be judged, so nothing may run, and nothing is cached either.
            return GitConfigVerdict(
                refusedKeys: [Self.unreadableConfiguration], filterDrivers: [], entries: [],
                userCredentialHelpers: [], files: [])
        }
        let verdict = GitConfigPolicy.verdict(for: entries)
        store(verdict, forKey: key)
        return verdict
    }

    /// What a verdict names instead of a key when git's listing could not be read at all.
    public static let unreadableConfiguration = "(the configuration could not be read)"

    /// Forgets every cached verdict.
    public func removeAll() {
        storage.withLock { $0 = Storage() }
    }

    private func cachedVerdict(forKey key: Key) -> GitConfigVerdict? {
        storage.withLock { storage in
            guard let entry = storage.entries[key] else { return nil }
            guard entry.stamps.allSatisfy({ $0.isCurrent }) else {
                storage.entries[key] = nil
                storage.order.removeAll { $0 == key }
                return nil
            }
            return entry.verdict
        }
    }

    private func store(_ verdict: GitConfigVerdict, forKey key: Key) {
        // A directory that holds no repository configuration is not a repository yet; caching that would hide one
        // appearing later, and nothing reads such a directory often enough for the cost to matter.
        guard !verdict.files.isEmpty else { return }
        var stamps = verdict.files.map(GitFileStamp.read)
        stamps += Set(verdict.files.map { ($0 as NSString).deletingLastPathComponent }).sorted()
            .map(GitFileStamp.read)
        storage.withLock { storage in
            if storage.entries[key] == nil { storage.order.append(key) }
            storage.entries[key] = Entry(verdict: verdict, stamps: stamps)
            while storage.order.count > capacity {
                storage.entries[storage.order.removeFirst()] = nil
            }
        }
    }
}

/// What one file looked like when a verdict was read, so the next call can tell whether it still does.
private struct GitFileStamp: Sendable, Hashable {
    let path: String
    /// nil when the file did not exist; a file appearing later is a change too.
    let identity: Identity?

    struct Identity: Sendable, Hashable {
        let device: Int64
        let inode: UInt64
        let size: Int64
        let seconds: Int64
        let nanoseconds: Int64
    }

    static func read(_ path: String) -> GitFileStamp {
        var status = stat()
        guard path.withCString({ stat($0, &status) }) == 0 else { return GitFileStamp(path: path, identity: nil) }
        return GitFileStamp(
            path: path,
            identity: Identity(
                device: Int64(status.st_dev), inode: status.st_ino, size: status.st_size,
                seconds: Int64(status.st_mtimespec.tv_sec), nanoseconds: Int64(status.st_mtimespec.tv_nsec)))
    }

    var isCurrent: Bool {
        Self.read(path) == self
    }
}

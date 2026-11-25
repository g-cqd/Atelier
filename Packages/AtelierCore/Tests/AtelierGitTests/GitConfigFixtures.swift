import AtelierProcess
import AtelierTestSupport
import Foundation

@testable import AtelierGit

/// One entry of a scripted `git config --list -z --includes --show-scope --show-origin` listing.
struct GitConfigLine {
    let scope: GitConfigScope
    let file: String
    let key: String
    let value: String?

    init(_ scope: GitConfigScope = .local, _ key: String, _ value: String? = "1", file: String = "/nowhere/config") {
        self.scope = scope
        self.key = key
        self.value = value
        self.file = file
    }
}

/// The listing git prints for `lines`: three NUL-terminated fields per entry, the value after the key's first
/// newline, and no value at all for a key written without one.
func gitConfigListing(_ lines: [GitConfigLine]) -> String {
    lines.map { line in
        let pair = line.value.map { "\(line.key)\n\($0)" } ?? line.key
        return "\(line.scope.rawValue)\0file:\(line.file)\0\(pair)\0"
    }
    .joined()
}

/// What an ordinary checkout looks like: the keys `git init` and `git remote add` write, plus the third-party ones
/// the audit found in the user's own repositories.
let ordinaryRepositoryLines: [GitConfigLine] = [
    GitConfigLine(.system, "credential.helper", "osxkeychain", file: "/opt/homebrew/etc/gitconfig"),
    GitConfigLine(.global, "filter.lfs.clean", "git-lfs clean -- %f", file: "/Users/t/.gitconfig"),
    GitConfigLine(.local, "core.repositoryformatversion", "0"),
    GitConfigLine(.local, "core.filemode", "true"),
    GitConfigLine(.local, "core.bare", "false"),
    GitConfigLine(.local, "core.logallrefupdates", "true"),
    GitConfigLine(.local, "core.ignorecase", "true"),
    GitConfigLine(.local, "core.precomposeunicode", "true"),
    GitConfigLine(.local, "core.hookspath", ".husky/_"),
    GitConfigLine(.local, "remote.origin.url", "git@github.com:aemi/atelier.git"),
    GitConfigLine(.local, "remote.origin.fetch", "+refs/heads/*:refs/remotes/origin/*"),
    GitConfigLine(.local, "remote.origin.gh-resolved", "base"),
    GitConfigLine(.local, "branch.main.remote", "origin"),
    GitConfigLine(.local, "branch.main.merge", "refs/heads/main"),
    GitConfigLine(.local, "branch.main.vscode-merge-base", "origin/main"),
    GitConfigLine(.local, "rerere.enabled", "true"),
    GitConfigLine(.local, "submodule.sub.url", "https://example.com/sub.git"),
    GitConfigLine(.worktree, "extensions.worktreeconfig", "true")
]

extension FakeProcessRunner {
    /// A runner that answers the configuration read with `lines` and every other spec through `handler`.
    static func gated(_ lines: [GitConfigLine], _ handler: @escaping @Sendable (ProcessSpec) -> ProcessOutput)
        -> FakeProcessRunner
    {
        let listing = gitConfigListing(lines)
        return FakeProcessRunner { spec in
            spec.isConfigurationRead ? .success(listing) : handler(spec)
        }
    }

    /// A runner that approves an ordinary checkout and answers every command with `output`.
    static func gated(always output: ProcessOutput) -> FakeProcessRunner {
        gated(ordinaryRepositoryLines) { _ in output }
    }

    /// Every spec but the configuration reads, in order.
    var commandSpecs: [ProcessSpec] { specs.filter { !$0.isConfigurationRead } }
}

extension ProcessSpec {
    /// True for the read ``GitConfigPolicy`` makes before a command runs.
    var isConfigurationRead: Bool { arguments.contains("--show-scope") }
}

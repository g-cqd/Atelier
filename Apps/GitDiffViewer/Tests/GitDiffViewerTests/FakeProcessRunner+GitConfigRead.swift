import AtelierTestSupport
import DiffGit

/// The configuration read `GitClient` makes before every git command, scripted away so a test's handler only sees
/// the commands it is about. A local copy of `AtelierGitTests`' fixture, which an app test target cannot import.
extension FakeProcessRunner {
    /// A runner that approves the repository and answers every other spec through `handler`. Each of `remotes` becomes
    /// the repository's own `remote.<name>.url`, so a fetch has a URL to go to. The entries name no configuration
    /// file, so the gate the production code shares never caches them and no test sees another's remotes.
    static func gated(remotes: [String: String] = [:], _ handler: @escaping Handler) -> FakeProcessRunner {
        let listing = remotes.map { name, url in "local\0blob:scripted\0remote.\(name).url\n\(url)\0" }.joined()
        return FakeProcessRunner { spec in
            spec.isConfigurationRead ? .success(listing) : try await handler(spec)
        }
    }

    /// Every spec but the configuration reads, in order.
    var commandSpecs: [ProcessSpec] { specs.filter { !$0.isConfigurationRead } }
}

extension ProcessSpec {
    /// True for the read ``GitConfigPolicy`` makes before a command runs.
    var isConfigurationRead: Bool {
        arguments.suffix(GitConfigPolicy.listingArguments.count).elementsEqual(GitConfigPolicy.listingArguments)
    }
}

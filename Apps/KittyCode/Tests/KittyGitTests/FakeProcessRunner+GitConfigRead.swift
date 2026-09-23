import AtelierGit
import AtelierProcess
import AtelierTestSupport

/// The configuration read `GitClient` makes before every git command, scripted away so a test's handler only sees
/// the commands it is about. A local copy of `AtelierGitTests`' fixture, which an app test target cannot import.
extension FakeProcessRunner {
    /// A runner that approves the repository, which holds no key of its own, and answers every other spec through
    /// `handler`. An approval with no configuration file is never cached, so no test sees another's verdict.
    static func gated(_ handler: @escaping Handler) -> FakeProcessRunner {
        FakeProcessRunner { spec in
            spec.isConfigurationRead ? .success("") : try await handler(spec)
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

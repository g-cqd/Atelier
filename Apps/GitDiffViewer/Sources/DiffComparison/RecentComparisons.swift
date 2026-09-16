import DiffCore
import DiffGit
import DiffRendering
package import Foundation
import Observation

/// The comparisons opened lately, newest first, persisted in user defaults for the welcome window. One entry per
/// repository, file pair or patch: opening a repository again with other refs replaces its entry.
@Observable
@MainActor
package final class RecentComparisons {
    package private(set) var entries: [LaunchConfiguration] = []
    package static let limit = 20

    private let defaults: UserDefaults

    package init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        entries =
            defaults.data(forKey: Key.entries)
            .flatMap { try? JSONDecoder().decode([LaunchConfiguration].self, from: $0) } ?? []
    }

    package func record(_ configuration: LaunchConfiguration) {
        entries.removeAll { $0.identity == configuration.identity }
        entries.insert(configuration, at: 0)
        entries = Array(entries.prefix(Self.limit))
        save()
    }

    package func remove(_ configuration: LaunchConfiguration) {
        entries.removeAll { $0 == configuration }
        save()
    }

    package func clear() {
        entries = []
        save()
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(entries), forKey: Key.entries)
    }

    private enum Key {
        static let entries = "recentComparisons"
    }
}

extension LaunchConfiguration {
    /// What makes two entries the same comparison target, refs aside.
    package var identity: String {
        switch self {
            case .patch(let url): "patch:" + url.standardizedFileURL.path(percentEncoded: false)
            case .files(let left, let right):
                "files:" + left.standardizedFileURL.path(percentEncoded: false) + "\u{0}"
                    + right.standardizedFileURL.path(percentEncoded: false)
            case .repository(let url, _, _): "repository:" + url.standardizedFileURL.path(percentEncoded: false)
        }
    }
}

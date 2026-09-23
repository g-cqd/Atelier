import AemiTesting
import AtelierGit
import Foundation
import KittyFileTree
import KittyWorkspace
import Testing

@testable import KittyEditor

/// The git refresh and autosave intervals feed `Duration.seconds` in a sleep loop: a zero or negative interval runs
/// the loop back to back, and a huge one traps converting to `Duration`.
@Suite
struct ConfigIntervalTests {
    enum Interval: CaseIterable, Sendable, CustomTestStringConvertible {
        case gitRefresh
        case autoSave

        var testDescription: String {
            switch self {
                case .gitRefresh: "git.refreshInterval"
                case .autoSave: "autoSave.interval"
            }
        }

        var defaultValue: TimeInterval {
            switch self {
                case .gitRefresh: 10
                case .autoSave: 30
            }
        }

        var keyPath: WritableKeyPath<KittyConfig, TimeInterval> {
            switch self {
                case .gitRefresh: \.git.refreshInterval
                case .autoSave: \.autoSave.interval
            }
        }

        /// A config file setting only this interval, to `value` written as JSON.
        func configJSON(_ value: String) -> String {
            switch self {
                case .gitRefresh: #"{"git": {"refreshInterval": \#(value)}}"#
                case .autoSave: #"{"autoSave": {"interval": \#(value)}}"#
            }
        }
    }

    /// Decodes with a decoder that also reads NaN and the infinities, which plain JSON cannot hold.
    private static func decode(_ json: String) throws -> KittyConfig {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return try decoder.decode(KittyConfig.self, from: Data(json.utf8))
    }

    @Test(arguments: Interval.allCases, ["0", "-5", "0.25"])
    func `an interval under a second decodes as one second`(interval: Interval, value: String) throws {
        let config = try Self.decode(interval.configJSON(value))
        #expect(config[keyPath: interval.keyPath] == 1)
    }

    @Test(arguments: Interval.allCases, ["1e300", "86400"])
    func `an interval over an hour decodes as an hour`(interval: Interval, value: String) throws {
        let config = try Self.decode(interval.configJSON(value))
        #expect(config[keyPath: interval.keyPath] == 3_600)
    }

    @Test(arguments: Interval.allCases, [#""nan""#, #""inf""#, #""-inf""#])
    func `a non-finite interval decodes as the default`(interval: Interval, value: String) throws {
        let config = try Self.decode(interval.configJSON(value))
        #expect(config[keyPath: interval.keyPath] == interval.defaultValue)
    }

    @Test(arguments: Interval.allCases, [1, 2.5, 3_600])
    func `an interval within bounds decodes unchanged`(interval: Interval, value: Double) throws {
        let config = try Self.decode(interval.configJSON(String(value)))
        #expect(config[keyPath: interval.keyPath] == value)
    }

    @Test(arguments: Interval.allCases, [0, -5, 1e300, .nan, .infinity, -.infinity])
    func `an interval set in code stays finite and within bounds`(interval: Interval, value: Double) {
        var config = KittyConfig()
        config[keyPath: interval.keyPath] = value
        let stored = config[keyPath: interval.keyPath]
        #expect(stored.isFinite && KittyConfig.intervalRange.contains(stored))
    }

    /// Counts `refresh()` calls, the git refresh loop's only effect when no decoration manager is wired.
    private struct RefreshCounter: FileStatusProvider {
        let refreshes = CountProbe()
        var branchName: String? { nil }
        var summary: FileStatusSummary { FileStatusSummary() }

        func status(for path: String) -> FileStatus? { nil }

        func refresh() async { refreshes.record() }
    }

    @Test
    @MainActor
    func `a git refresh loop configured with a zero interval waits a second between refreshes`() async throws {
        let config = try Self.decode(Interval.gitRefresh.configJSON("0"))
        // With a zero interval the loop's sleep returns at once, so it would never queue a sleeper to wait for.
        try #require(config.git.refreshInterval >= 1)
        let clock = TestClock()
        let counter = RefreshCounter()
        let manager = GitRefreshManager(
            fileStatusProvider: counter, gitDecorationManager: nil, refreshInterval: config.git.refreshInterval,
            invalidateRender: {}, taskProvider: TaskProviderSpy(), clock: clock)
        manager.start()
        defer { manager.stop() }

        for refreshes in 1 ... 2 {
            try await clock.waitForSleepers(count: 1)
            clock.advance(by: .milliseconds(999))
            #expect(counter.refreshes.count == refreshes - 1)
            let mark = clock.registrationMark()
            clock.advance(by: .milliseconds(1))
            try await clock.waitForSleepers(1, after: mark)
            #expect(counter.refreshes.count == refreshes)
        }
    }
}

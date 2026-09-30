import Foundation
import Testing

@testable import DiffTextKit

/// The Settings ▸ Beta tab (book D44): its "Text Engine" picker is a plain `@AppStorage(TextBackendKind.defaultsKey)`,
/// not a ``DiffComparison/ViewerSettings`` property, so what it persists is checked directly against the key it
/// shares with a new window's own read of the default (``TextBackendKind/developerDefault(environment:stored:)``),
/// the same key `DevelopCommands`'s Beta menu and `ComparisonWindow` read. The key is spelled out because it is what
/// users' defaults hold.
struct BetaSettingsTests {
    private let scratchDefaults = ScratchDefaults(tag: "beta")

    @Test
    func `the key BetaSettings persists under is the one a new window reads its default from`() {
        #expect(TextBackendKind.defaultsKey == "developer.textBackend")
    }

    @Test
    func `off by default, a fresh suite starts a new window on TextKit 2`() {
        let defaults = scratchDefaults.defaults

        let kind = TextBackendKind.developerDefault(
            environment: [:], stored: defaults.string(forKey: TextBackendKind.defaultsKey))

        #expect(kind == .textKit2)
    }

    @Test
    func `choosing CoreText in Beta settings persists and a new window reads it back`() {
        let defaults = scratchDefaults.defaults
        defaults.set(TextBackendKind.coreText.rawValue, forKey: TextBackendKind.defaultsKey)

        let kind = TextBackendKind.developerDefault(
            environment: [:], stored: defaults.string(forKey: TextBackendKind.defaultsKey))

        #expect(kind == .coreText)
    }

    @Test
    func `restoring defaults clears the stored choice back to TextKit 2`() {
        let defaults = scratchDefaults.defaults
        defaults.set(TextBackendKind.coreText.rawValue, forKey: TextBackendKind.defaultsKey)

        defaults.set(TextBackendKind.textKit2.rawValue, forKey: TextBackendKind.defaultsKey)

        let kind = TextBackendKind.developerDefault(
            environment: [:], stored: defaults.string(forKey: TextBackendKind.defaultsKey))
        #expect(kind == .textKit2)
    }
}

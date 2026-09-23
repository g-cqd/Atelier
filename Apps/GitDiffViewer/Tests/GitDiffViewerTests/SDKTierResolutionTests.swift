import AtelierLSP
import Foundation
import Synchronization
import Testing

@testable import DiffComparison

@MainActor
struct SDKTierResolutionTests {
    @Test
    func `the tier finds the iOS SDK once, while it resolves`() async throws {
        let name = "GitDiffViewerTests.sdkTier.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        let policy = LanguageServerPolicy(
            trust: RepositoryTrust(defaults: defaults), defaults: defaults,
            locate: { _ in URL(filePath: "/usr/bin/false") })
        let asked = Mutex<[SDKPlatform]>([])

        let resolved = try #require(
            await policy.resolveSDKTier { platform in
                asked.withLock { $0.append(platform) }
                return nil
            })
        defer { try? FileManager.default.removeItem(at: resolved.probeDirectory) }

        #expect(asked.withLock { $0 } == [.iOS])
    }
}

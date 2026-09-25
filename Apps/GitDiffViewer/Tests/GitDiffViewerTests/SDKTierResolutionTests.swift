import AtelierLSP
import Foundation
import Synchronization
import Testing

@testable import DiffComparison

@MainActor
struct SDKTierResolutionTests {
    private let scratchDefaults = ScratchDefaults(tag: "sdkTier")

    @Test
    func `the tier finds the iOS SDK once, while it resolves`() async throws {
        let defaults = scratchDefaults.defaults
        let policy = LanguageServerPolicy(
            trust: RepositoryTrust(defaults: defaults), defaults: defaults,
            locate: { _, _ in URL(filePath: "/usr/bin/false") })
        let asked = Mutex<[SDKPlatform]>([])

        let resolved = try #require(
            await policy.resolveSDKTier { platform in
                asked.withLock { $0.append(platform) }
                return nil
            })

        #expect(asked.withLock { $0 } == [.iOS])
        try FileManager.default.removeItem(at: resolved.probeDirectory)
    }
}

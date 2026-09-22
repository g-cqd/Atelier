import AtelierDiagnostics
import Testing

@testable import DiffComparison

/// ``sourceKitLSPDiscoveryEnabled(_:)``: the shared gate that must block discovery outright once sourcekit-lsp is
/// disabled, not merely clear its custom path.
struct SourceKitLSPDiscoveryGateTests {
    @Test("Never configured defaults to enabled, like every other tool")
    func neverConfiguredDefaultsEnabled() {
        #expect(sourceKitLSPDiscoveryEnabled(nil))
    }

    @Test("An explicitly enabled location stays enabled")
    func explicitlyEnabled() {
        #expect(sourceKitLSPDiscoveryEnabled(ToolLocation(isEnabled: true, customPath: "/usr/bin/sourcekit-lsp")))
    }

    @Test("A disabled location gates discovery regardless of a leftover custom path")
    func disabledGatesDiscovery() {
        #expect(!sourceKitLSPDiscoveryEnabled(ToolLocation(isEnabled: false, customPath: "/usr/bin/sourcekit-lsp")))
        #expect(!sourceKitLSPDiscoveryEnabled(ToolLocation(isEnabled: false, customPath: nil)))
    }
}

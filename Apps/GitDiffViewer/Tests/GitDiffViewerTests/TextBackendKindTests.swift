import Foundation
import Testing

@testable import DiffTextKit

/// The backend a new window starts with (text-renderer.md §4.3): the environment's, else the hidden default's, else
/// TextKit 2.
struct TextBackendKindTests {
    @Test
    func `a window starts with TextKit 2 when nothing picks a backend`() {
        #expect(TextBackendKind.developerDefault(environment: [:], stored: nil) == .textKit2)
    }

    @Test
    func `the environment picks the backend over the defaults`() {
        let kind = TextBackendKind.developerDefault(
            environment: [TextBackendKind.environmentKey: "textKit2"], stored: "unknown")
        #expect(kind == .textKit2)
    }

    @Test
    func `a name no backend has is passed over`() {
        let kind = TextBackendKind.developerDefault(
            environment: [TextBackendKind.environmentKey: "metal"], stored: "textKit2")
        #expect(kind == .textKit2)
        #expect(TextBackendKind(rawValue: "metal") == nil)
    }
}

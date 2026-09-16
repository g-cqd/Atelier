import Foundation
import Testing

@testable import KittyCodecs

@Suite
struct NotificationsTests {
    @Test
    func `notify with title only produces single OSC 99 sequence`() {
        let bytes = KittySequences.notify(title: "Build done")
        let asString = String(bytes: bytes, encoding: .utf8) ?? ""
        #expect(asString.contains("99;i=1:d=0:p=title;Build done"))
        // Should not have body part
        #expect(!asString.contains("p=body"))
        // Single ST at end
        #expect(bytes[bytes.count - 2] == 0x1b)
        #expect(bytes[bytes.count - 1] == 0x5c)
    }

    @Test
    func `notify with title and body produces two OSC 99 sequences`() {
        let bytes = KittySequences.notify(title: "Alert", body: "Check logs")
        let asString = String(bytes: bytes, encoding: .utf8) ?? ""
        #expect(asString.contains("p=title;Alert"))
        #expect(asString.contains("p=body;Check logs"))
    }

    @Test
    func `notify with empty body produces title-only sequence`() {
        let bytes = KittySequences.notify(title: "Test", body: "")
        let asString = String(bytes: bytes, encoding: .utf8) ?? ""
        #expect(!asString.contains("p=body"))
    }
}

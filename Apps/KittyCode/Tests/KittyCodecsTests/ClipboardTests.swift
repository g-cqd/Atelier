import Foundation
import Testing

@testable import KittyCodecs

@Suite
struct ClipboardTests {
    @Test
    func `setClipboard produces OSC 52 sequence`() {
        let bytes = KittySequences.setClipboard("SGVsbG8=")  // "Hello" in base64
        // OSC 52 ; c ; <base64> ST
        #expect(bytes[0] == 0x1b)
        #expect(bytes[1] == 0x5d)  // ] (OSC)
        let body = String(bytes: Array(bytes[2 ..< bytes.count - 2]), encoding: .utf8) ?? ""
        #expect(body == "52;c;SGVsbG8=")
        #expect(bytes[bytes.count - 2] == 0x1b)
        #expect(bytes[bytes.count - 1] == 0x5c)
    }

    @Test
    func `requestClipboard produces OSC 52 query`() {
        let bytes = KittySequences.requestClipboard
        let expected: [UInt8] = [0x1b, 0x5d] + "52;c;?".utf8 + [0x1b, 0x5c]
        #expect(bytes == expected)
    }

    @Test
    func `setClipboard with empty string produces valid sequence`() {
        let bytes = KittySequences.setClipboard("")
        let expected: [UInt8] = [0x1b, 0x5d] + "52;c;".utf8 + [0x1b, 0x5c]
        #expect(bytes == expected)
    }
}

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

    @Test(arguments: ["\u{07}", "\u{1B}\\"])
    func `a clipboard reply decodes its base64 to text, whichever terminator ends it`(terminator: String) {
        let reply = Array("\u{1B}]52;c;SGVsbG8=\(terminator)".utf8)
        #expect(OSCClipboard.parse(reply) == .text("Hello"))
    }

    @Test
    func `a clipboard reply with no payload reads as empty`() {
        #expect(OSCClipboard.parse(Array("\u{1B}]52;c;\u{1B}\\".utf8)) == .empty)
    }

    @Test
    func `a clipboard reply whose payload is not base64 reads as unreadable`() {
        #expect(OSCClipboard.parse(Array("\u{1B}]52;c;not base64!\u{07}".utf8)) == .unreadable)
    }

    @Test
    func `invalid UTF-8 in the clipboard becomes a replacement character`() {
        let payload = Data([0x61, 0xFF, 0x62]).base64EncodedString()
        #expect(OSCClipboard.parse(Array("\u{1B}]52;c;\(payload)\u{07}".utf8)) == .text("a\u{FFFD}b"))
    }

    @Test(arguments: ["\u{1B}]10;rgb:ffff/ffff/ffff\u{07}", "\u{1B}[?62;22c", "\u{1B}]52;c\u{07}", "\u{1B}]52;c;SGk="])
    func `bytes that are no complete OSC 52 reply are not a clipboard reply`(sequence: String) {
        #expect(OSCClipboard.parse(Array(sequence.utf8)) == nil)
    }
}

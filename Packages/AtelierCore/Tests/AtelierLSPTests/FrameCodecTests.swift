import Foundation
import Testing

@testable import AtelierLSP

@Suite
struct FrameCodecTests {
    @Test
    func `Single message split at every byte boundary`() {
        let payload = Data(#"{"jsonrpc":"2.0","method":"initialized","params":{}}"#.utf8)
        let framed = LSPFrameCodec.frame(payload)

        for split in 1 ..< framed.count {
            var codec = LSPFrameCodec()
            let prefix = framed[framed.startIndex ..< framed.index(framed.startIndex, offsetBy: split)]
            let suffix = framed[framed.index(framed.startIndex, offsetBy: split)...]

            let fromPrefix = try? codec.feed(Data(prefix))
            #expect(fromPrefix?.isEmpty == true)

            let fromSuffix = try? codec.feed(Data(suffix))
            #expect(fromSuffix == [payload])
        }
    }

    @Test
    func `Two messages arrive in one chunk`() throws {
        let first = Data(#"{"a":1}"#.utf8)
        let second = Data(#"{"b":2}"#.utf8)
        var chunk = LSPFrameCodec.frame(first)
        chunk.append(LSPFrameCodec.frame(second))

        var codec = LSPFrameCodec()
        let payloads = try codec.feed(chunk)
        #expect(payloads == [first, second])
    }

    @Test
    func `Header name is case insensitive`() throws {
        let payload = Data(#"{"a":1}"#.utf8)
        var chunk = Data("content-length: \(payload.count)\r\n\r\n".utf8)
        chunk.append(payload)

        var codec = LSPFrameCodec()
        let payloads = try codec.feed(chunk)
        #expect(payloads == [payload])
    }

    @Test
    func `Content-Type header is ignored`() throws {
        let payload = Data(#"{"a":1}"#.utf8)
        var chunk = Data(
            "Content-Length: \(payload.count)\r\nContent-Type: application/vscode-jsonrpc; charset=utf-8\r\n\r\n"
                .utf8)
        chunk.append(payload)

        var codec = LSPFrameCodec()
        let payloads = try codec.feed(chunk)
        #expect(payloads == [payload])
    }

    @Test
    func `Malformed header line throws`() {
        let chunk = Data("Not-A-Header-Line\r\n\r\n".utf8)
        var codec = LSPFrameCodec()
        #expect(throws: LSPFramingError.self) {
            _ = try codec.feed(chunk)
        }
    }

    @Test
    func `Missing content length throws`() {
        let chunk = Data("Content-Type: application/vscode-jsonrpc\r\n\r\n".utf8)
        var codec = LSPFrameCodec()
        #expect(throws: LSPFramingError.missingContentLength) {
            _ = try codec.feed(chunk)
        }
    }

    @Test
    func `Oversize payload throws`() {
        let chunk = Data("Content-Length: 100\r\n\r\n".utf8)
        var codec = LSPFrameCodec(maximumPayloadSize: 10)
        #expect(throws: LSPFramingError.payloadTooLarge(100)) {
            _ = try codec.feed(chunk)
        }
    }

    @Test
    func `a 9 KiB header without a terminator throws`() {
        let header = Data(repeating: UInt8(ascii: "x"), count: 9 * 1024)
        var codec = LSPFrameCodec()
        #expect(throws: LSPFramingError.headerTooLarge) {
            _ = try codec.feed(header)
        }
    }

    @Test
    func `a header one byte past the maximum throws before its terminator ends`() {
        let header = Data(repeating: UInt8(ascii: "x"), count: LSPFrameCodec.maximumHeaderSize + 1)
        var codec = LSPFrameCodec()
        #expect(throws: LSPFramingError.headerTooLarge) {
            _ = try codec.feed(header + Data("\r\n\r".utf8))
        }
    }

    @Test
    func `a header of the maximum size still frames its payload when its terminator arrives last`() throws {
        let payload = Data(#"{"a":1}"#.utf8)
        let lengthLine = "Content-Length: \(payload.count)\r\n"
        let paddingName = "X-Padding: "
        let padding = String(
            repeating: "p", count: LSPFrameCodec.maximumHeaderSize - lengthLine.utf8.count - paddingName.utf8.count)
        var framed = Data((lengthLine + paddingName + padding + "\r\n\r\n").utf8)
        framed.append(payload)
        // Everything but the terminator's last byte: the codec must keep waiting rather than refuse the header.
        let split = LSPFrameCodec.maximumHeaderSize + 3

        var codec = LSPFrameCodec()
        #expect(try codec.feed(framed.prefix(split)) == [])
        #expect(try codec.feed(framed.dropFirst(split)) == [payload])
    }

    @Test
    func `frame produces exact bytes`() {
        let payload = Data(#"{"a":1}"#.utf8)
        let framed = LSPFrameCodec.frame(payload)
        var expected = Data("Content-Length: \(payload.count)\r\n\r\n".utf8)
        expected.append(payload)
        #expect(framed == expected)
    }
}

public import Foundation

/// Why a chunk fed to ``LSPFrameCodec`` could not be turned into complete frames.
public enum LSPFramingError: Error, Equatable, Sendable {
    /// A header line was neither `Name: value` nor blank.
    case malformedHeader(String)
    /// The header block ended without a `Content-Length` header.
    case missingContentLength
    /// The declared length was negative.
    case negativeContentLength(Int)
    /// The declared length exceeded the codec's configured maximum.
    case payloadTooLarge(Int)
}

/// Incremental parser for the LSP base protocol's `Content-Length` framing.
///
/// Feed it chunks as they arrive from the transport, in any split; it buffers until each frame
/// is complete and returns the payloads it can extract, in order.
public struct LSPFrameCodec: Sendable {
    private static let headerTerminator = Data("\r\n\r\n".utf8)

    private let maximumPayloadSize: Int
    private var buffer: Data

    public init(maximumPayloadSize: Int = 64 << 20) {
        self.maximumPayloadSize = maximumPayloadSize
        self.buffer = Data()
    }

    /// Feeds a chunk read from the transport; returns every complete payload now available, in order.
    public mutating func feed(_ chunk: Data) throws(LSPFramingError) -> [Data] {
        buffer.append(chunk)

        var payloads: [Data] = []
        while let headerEnd = buffer.range(of: Self.headerTerminator) {
            let headerData = buffer[buffer.startIndex ..< headerEnd.lowerBound]
            let contentLength = try Self.parseContentLength(headerData)

            guard contentLength >= 0 else {
                throw LSPFramingError.negativeContentLength(contentLength)
            }

            guard contentLength <= maximumPayloadSize else {
                throw LSPFramingError.payloadTooLarge(contentLength)
            }

            let payloadStart = headerEnd.upperBound
            guard let payloadEnd = buffer.index(payloadStart, offsetBy: contentLength, limitedBy: buffer.endIndex)
            else {
                break
            }

            payloads.append(Data(buffer[payloadStart ..< payloadEnd]))
            buffer.removeSubrange(buffer.startIndex ..< payloadEnd)
        }

        return payloads
    }

    /// Wraps `payload` in a `Content-Length` header, ready to write to the transport.
    public static func frame(_ payload: Data) -> Data {
        var framed = Data("Content-Length: \(payload.count)\r\n\r\n".utf8)
        framed.append(payload)
        return framed
    }

    private static func parseContentLength(_ headerData: Data) throws(LSPFramingError) -> Int {
        let headerText = String(decoding: headerData, as: UTF8.self)
        let lines = headerText.split(separator: "\r\n", omittingEmptySubsequences: true)

        var contentLength: Int?
        for line in lines {
            guard let colonIndex = line.firstIndex(of: ":") else {
                throw LSPFramingError.malformedHeader(String(line))
            }
            let name = String(line[line.startIndex ..< colonIndex]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)

            guard name.caseInsensitiveCompare("Content-Length") == .orderedSame else { continue }
            guard let length = Int(value) else {
                throw LSPFramingError.malformedHeader(String(line))
            }
            contentLength = length
        }

        guard let contentLength else { throw LSPFramingError.missingContentLength }
        return contentLength
    }
}

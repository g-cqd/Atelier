import Foundation

/// Encodes Kitty graphics protocol commands.
///
/// Format: `ESC_G <control>;...;<payload> ESC\`
/// Payload is base64-encoded, chunked at 4096 bytes.
public enum GraphicsEncoder: Sendable {

    private static let chunkSize = 4096

    /// Encodes a graphics command into one or more Kitty APC chunks.
    ///
    /// The command payload is base64-encoded and split into chunks of at most 4096 bytes.
    /// When multiple chunks are required the first carries the full control header and
    /// subsequent chunks carry only the continuation marker (`m=1`/`m=0`).
    ///
    /// - Parameter command: The graphics command to encode, including action, format, transmission,
    ///   dimensions, and raw payload bytes.
    /// - Returns: Raw bytes for the complete sequence of `ESC _ G ... ESC \` APC frames.
    public static func encode(_ command: GraphicsCommand) -> [UInt8] {
        let controlPart = buildControl(command)
        let base64Payload = Data(command.payload).base64EncodedString()

        if base64Payload.count <= chunkSize {
            return buildChunk(control: controlPart, payload: base64Payload, more: false)
        }

        // Multi-chunk: first chunk has control data, subsequent chunks only have payload
        var result: [UInt8] = []
        var offset = base64Payload.startIndex

        var isFirst = true
        while offset < base64Payload.endIndex {
            let end = base64Payload.index(offset, offsetBy: chunkSize, limitedBy: base64Payload.endIndex)
                ?? base64Payload.endIndex
            let chunk = String(base64Payload[offset..<end])
            let hasMore = end < base64Payload.endIndex

            if isFirst {
                result.append(contentsOf: buildChunk(control: controlPart, payload: chunk, more: hasMore))
                isFirst = false
            } else {
                result.append(contentsOf: buildChunk(control: "m=\(hasMore ? 1 : 0)", payload: chunk, more: false))
            }

            offset = end
        }

        return result
    }

    private static func buildControl(_ cmd: GraphicsCommand) -> String {
        var parts: [String] = []
        parts.append("a=\(cmd.action.rawValue)")
        parts.append("f=\(cmd.format.rawValue)")
        parts.append("t=\(cmd.transmission.rawValue)")
        if cmd.id > 0 { parts.append("i=\(cmd.id)") }
        if cmd.width > 0 { parts.append("s=\(cmd.width)") }
        if cmd.height > 0 { parts.append("v=\(cmd.height)") }
        return parts.joined(separator: ",")
    }

    private static func buildChunk(control: String, payload: String, more: Bool) -> [UInt8] {
        var bytes: [UInt8] = []
        // ESC_G = ESC ] _ in APC form, but Kitty uses ESC_G as custom
        // Actually: APC = ESC _ ... ST (ESC \)
        bytes.append(0x1b) // ESC
        bytes.append(0x5f) // _ (APC)
        bytes.append(contentsOf: "G".utf8)
        if more {
            bytes.append(contentsOf: "\(control),m=1".utf8)
        } else {
            bytes.append(contentsOf: control.utf8)
        }
        bytes.append(0x3b) // ;
        bytes.append(contentsOf: payload.utf8)
        bytes.append(0x1b) // ESC
        bytes.append(0x5c) // \ (ST)
        return bytes
    }
}

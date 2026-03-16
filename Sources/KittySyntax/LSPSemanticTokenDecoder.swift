/// Describes the LSP semantic token legend (token types and modifiers).
public struct SemanticTokensLegend: Sendable, Equatable {
    public let tokenTypes: [String]
    public let tokenModifiers: [String]

    public init(tokenTypes: [String], tokenModifiers: [String] = []) {
        self.tokenTypes = tokenTypes
        self.tokenModifiers = tokenModifiers
    }
}

/// Decodes LSP delta-encoded `[UInt32]` semantic tokens into `[HighlightToken]`.
///
/// LSP encodes tokens as groups of 5 integers:
/// `[deltaLine, deltaStartChar, length, tokenType, tokenModifiers]`
///
/// This decoder converts them into absolute byte ranges using the source text
/// and maps token types/modifiers through `CaptureRoleMapper`.
public enum LSPSemanticTokenDecoder: Sendable {

    /// Decode LSP-encoded semantic tokens into `HighlightToken`s.
    ///
    /// - Parameters:
    ///   - data: Array of UInt32 values (groups of 5 per token)
    ///   - legend: The semantic token legend from the server's capabilities
    ///   - source: The source text the tokens apply to
    /// - Returns: Array of HighlightTokens at the `.semantic` layer
    public static func decode(
        data: [UInt32],
        legend: SemanticTokensLegend,
        source: String
    ) -> [HighlightToken] {
        guard data.count >= 5 else { return [] }

        // Build line start byte offsets
        let lineStarts = buildLineStarts(source)
        let utf8 = Array(source.utf8)

        var tokens: [HighlightToken] = []
        var currentLine: UInt32 = 0
        var currentChar: UInt32 = 0

        var i = 0
        while i + 4 < data.count {
            let deltaLine = data[i]
            let deltaStartChar = data[i + 1]
            let length = data[i + 2]
            let tokenTypeIdx = data[i + 3]
            let tokenModifierBits = data[i + 4]
            i += 5

            if deltaLine > 0 {
                currentLine += deltaLine
                currentChar = deltaStartChar
            } else {
                currentChar += deltaStartChar
            }

            guard Int(currentLine) < lineStarts.count else { continue }

            let lineStartByte = lineStarts[Int(currentLine)]
            // Convert character offset to byte offset (UTF-16 to UTF-8)
            let startByte = lineStartByte + charOffsetToByteOffset(
                utf8: utf8, lineStart: lineStartByte, charOffset: Int(currentChar))
            let endByte = startByte + charOffsetToByteOffset(
                utf8: utf8, lineStart: startByte, charOffset: Int(length))

            guard startByte < utf8.count, endByte <= utf8.count, startByte < endByte else {
                continue
            }

            let tokenType: String
            if Int(tokenTypeIdx) < legend.tokenTypes.count {
                tokenType = legend.tokenTypes[Int(tokenTypeIdx)]
            } else {
                tokenType = "variable"
            }

            let role = CaptureRoleMapper.mapLSPTokenType(tokenType)
            let modifiers = decodeLSPModifiers(tokenModifierBits, legend: legend)

            tokens.append(HighlightToken(
                byteRange: startByte..<endByte,
                role: role,
                modifiers: modifiers,
                layer: .semantic,
                priority: 0
            ))
        }

        return tokens
    }

    // MARK: - Private

    private static func buildLineStarts(_ source: String) -> [Int] {
        var starts = [0]
        for (i, byte) in source.utf8.enumerated() {
            if byte == 0x0A {  // newline
                starts.append(i + 1)
            }
        }
        return starts
    }

    private static func charOffsetToByteOffset(
        utf8: [UInt8], lineStart: Int, charOffset: Int
    ) -> Int {
        // Simple approximation: for ASCII, char == byte.
        // For multi-byte UTF-8, we walk forward counting UTF-16 code units.
        var bytePos = lineStart
        var charCount = 0

        while charCount < charOffset && bytePos < utf8.count {
            let byte = utf8[bytePos]
            if byte < 0x80 {
                bytePos += 1
                charCount += 1
            } else if byte < 0xC0 {
                // continuation byte — shouldn't start here, advance
                bytePos += 1
            } else if byte < 0xE0 {
                bytePos += 2
                charCount += 1
            } else if byte < 0xF0 {
                bytePos += 3
                charCount += 1
            } else {
                // 4-byte sequence = 2 UTF-16 code units (surrogate pair)
                bytePos += 4
                charCount += 2
            }
        }

        return bytePos - lineStart
    }

    private static func decodeLSPModifiers(
        _ bits: UInt32,
        legend: SemanticTokensLegend
    ) -> HighlightModifierSet {
        var modifiers = HighlightModifierSet()

        for (idx, name) in legend.tokenModifiers.enumerated() {
            guard bits & (1 << idx) != 0 else { continue }
            switch name {
            case "declaration":   modifiers.insert(.declaration)
            case "definition":    modifiers.insert(.definition)
            case "readonly":      modifiers.insert(.readonly)
            case "static":        modifiers.insert(.static)
            case "deprecated":    modifiers.insert(.deprecated)
            case "async":         modifiers.insert(.async)
            case "documentation": modifiers.insert(.documentation)
            default: break
            }
        }

        return modifiers
    }
}

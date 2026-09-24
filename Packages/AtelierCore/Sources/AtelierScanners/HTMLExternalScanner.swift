// Port of tree-sitter/tree-sitter-html/src/scanner.c at
// 5a5ca8551a179998360b4a4ca2c0f366a35acc03 (v0.23.2).
// MIT License. Copyright (c) 2014 Max Brunsfeld.
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

public import AtelierParser

/// The external scanner for the pinned HTML grammar, including its open-tag stack.
public struct HTMLExternalScanner: GrammarExternalScanner {
    private enum TokenType: Int {
        case startTagName
        case scriptStartTagName
        case styleStartTagName
        case endTagName
        case erroneousEndTagName
        case selfClosingTagDelimiter
        case implicitEndTag
        case rawText
        case comment
    }

    /// The bundled HTML grammar's `externals`, in order.
    public static let externalNames = [
        "_start_tag_name", "_script_start_tag_name", "_style_start_tag_name", "_end_tag_name",
        "erroneous_end_tag_name", "/>", "_implicit_end_tag", "raw_text", "comment"
    ]
    private static let scriptEndDelimiter = Array("</SCRIPT".utf8)
    private static let styleEndDelimiter = Array("</STYLE".utf8)

    private var tags: [HTMLTag] = []

    /// Creates a scanner with an empty open-tag stack.
    public init() {}

    /// Appends the C scanner's bounded stack representation to `buffer`.
    /// - Complexity: O(n), where n is the number of tags that fit in the serialized state.
    public func serialize(into buffer: inout [UInt8]) {
        let tagCount = min(tags.count, Int(UInt16.max))
        let header = buffer.count
        buffer.append(contentsOf: [0, 0, UInt8(truncatingIfNeeded: tagCount), UInt8(truncatingIfNeeded: tagCount >> 8)])
        var serializedTagCount = 0
        for tag in tags.prefix(tagCount) {
            if tag.type == .custom {
                let nameLength = min(tag.customName.count, Int(UInt8.max))
                if buffer.count - header + 2 + nameLength >= maximumSerializedScannerStateSize { break }
                buffer.append(tag.type.rawValue)
                buffer.append(UInt8(nameLength))
                buffer.append(contentsOf: tag.customName.prefix(nameLength))
            } else {
                if buffer.count - header + 1 >= maximumSerializedScannerStateSize { break }
                buffer.append(tag.type.rawValue)
            }
            serializedTagCount += 1
        }
        buffer[header] = UInt8(truncatingIfNeeded: serializedTagCount)
        buffer[header + 1] = UInt8(truncatingIfNeeded: serializedTagCount >> 8)
    }

    /// Restores a serialized open-tag stack; empty or malformed data clears it.
    /// - Complexity: O(n), where n is the restored tag count.
    public mutating func deserialize(_ state: ArraySlice<UInt8>) {
        tags.removeAll(keepingCapacity: true)
        guard !state.isEmpty else { return }
        guard state.count >= 4, state.count <= maximumSerializedScannerStateSize else { return }
        let bytes = Array(state)
        let serializedCount = Int(bytes[0]) | Int(bytes[1]) << 8
        let tagCount = Int(bytes[2]) | Int(bytes[3]) << 8
        guard serializedCount <= tagCount else { return }
        var restored: [HTMLTag] = []
        restored.reserveCapacity(tagCount)
        var offset = 4
        for _ in 0 ..< serializedCount {
            guard offset < bytes.count, let type = HTMLTagKind(rawValue: bytes[offset]) else { return }
            offset += 1
            if type == .custom {
                guard offset < bytes.count else { return }
                let length = Int(bytes[offset])
                offset += 1
                guard length <= bytes.count - offset else { return }
                restored.append(HTMLTag(type: .custom, customName: Array(bytes[offset ..< offset + length])))
                offset += length
            } else {
                restored.append(HTMLTag(type: type, customName: []))
            }
        }
        // The C scanner pads tags omitted when its serialization buffer filled.
        while restored.count < tagCount { restored.append(.empty) }
        tags = restored
    }

    private static func isSpace(_ value: UInt32) -> Bool {
        guard let scalar = Unicode.Scalar(value) else { return false }
        return scalar.properties.isWhitespace
    }

    private static func isAlnum(_ value: UInt32) -> Bool {
        guard let scalar = Unicode.Scalar(value) else { return false }
        return scalar.properties.isAlphabetic || scalar.properties.generalCategory == .decimalNumber
    }

    private static func uppercase(_ value: UInt32) -> UInt32 {
        guard let scalar = Unicode.Scalar(value) else { return value }
        let mapping = scalar.properties.uppercaseMapping.unicodeScalars
        return mapping.count == 1 ? mapping.first?.value ?? value : value
    }

    private static func scanTagName(_ lexer: inout some ScannerLexer) -> [UInt8] {
        var tagName: [UInt8] = []
        while isAlnum(lexer.lookahead) || lexer.lookahead == 0x2D || lexer.lookahead == 0x3A {
            tagName.append(UInt8(truncatingIfNeeded: uppercase(lexer.lookahead)))
            lexer.advance(skip: false)
        }
        return tagName
    }

    private static func scanComment(_ lexer: inout some ScannerLexer) -> Bool {
        guard lexer.lookahead == 0x2D else { return false }
        lexer.advance(skip: false)
        guard lexer.lookahead == 0x2D else { return false }
        lexer.advance(skip: false)

        var dashes = 0
        while lexer.lookahead != 0 {
            switch lexer.lookahead {
                case 0x2D:
                    dashes += 1
                case 0x3E:
                    if dashes >= 2 {
                        lexer.resultSymbol = TokenType.comment.rawValue
                        lexer.advance(skip: false)
                        lexer.markEnd()
                        return true
                    }
                    dashes = 0
                default:
                    dashes = 0
            }
            lexer.advance(skip: false)
        }
        return false
    }

    private func scanRawText(_ lexer: inout some ScannerLexer) -> Bool {
        guard let last = tags.last else { return false }
        lexer.markEnd()
        let endDelimiter = last.type == .script ? Self.scriptEndDelimiter : Self.styleEndDelimiter
        var delimiterIndex = 0
        while lexer.lookahead != 0 {
            if Self.uppercase(lexer.lookahead) == endDelimiter[delimiterIndex] {
                delimiterIndex += 1
                if delimiterIndex == endDelimiter.count { break }
                lexer.advance(skip: false)
            } else {
                delimiterIndex = 0
                lexer.advance(skip: false)
                lexer.markEnd()
            }
        }
        lexer.resultSymbol = TokenType.rawText.rawValue
        return true
    }

    private mutating func scanImplicitEndTag(_ lexer: inout some ScannerLexer) -> Bool {
        let parent = tags.last
        var isClosingTag = false
        if lexer.lookahead == 0x2F {
            isClosingTag = true
            lexer.advance(skip: false)
        } else if parent?.isVoid == true {
            tags.removeLast()
            lexer.resultSymbol = TokenType.implicitEndTag.rawValue
            return true
        }

        let tagName = Self.scanTagName(&lexer)
        if tagName.isEmpty && !lexer.isAtEnd { return false }
        let nextTag = HTMLTag.forName(tagName)
        if isClosingTag {
            // The tag correctly closes the topmost element on the stack.
            if tags.last == nextTag { return false }

            // Otherwise, dig deeper and queue implicit end tags (to be nice in
            // the case of malformed HTML).
            for tag in tags.reversed() where tag.type == nextTag.type {
                tags.removeLast()
                lexer.resultSymbol = TokenType.implicitEndTag.rawValue
                return true
            }
        } else if let parent,
            !parent.canContain(nextTag)
                || ((parent.type == .html || parent.type == .head || parent.type == .body) && lexer.isAtEnd)
        {
            tags.removeLast()
            lexer.resultSymbol = TokenType.implicitEndTag.rawValue
            return true
        }
        return false
    }

    private mutating func scanStartTagName(_ lexer: inout some ScannerLexer, validSymbols: [Bool]) -> Bool {
        let tagName = Self.scanTagName(&lexer)
        guard !tagName.isEmpty else { return false }
        let tag = HTMLTag.forName(tagName)
        let symbol: TokenType =
            switch tag.type {
                case .script: .scriptStartTagName
                case .style: .styleStartTagName
                default: .startTagName
            }
        guard validSymbols[symbol.rawValue] else { return false }
        tags.append(tag)
        lexer.resultSymbol = symbol.rawValue
        return true
    }

    private mutating func scanEndTagName(_ lexer: inout some ScannerLexer, validSymbols: [Bool]) -> Bool {
        let tagName = Self.scanTagName(&lexer)
        guard !tagName.isEmpty else { return false }
        let tag = HTMLTag.forName(tagName)
        if tags.last == tag {
            guard validSymbols[TokenType.endTagName.rawValue] else { return false }
            tags.removeLast()
            lexer.resultSymbol = TokenType.endTagName.rawValue
        } else {
            guard validSymbols[TokenType.erroneousEndTagName.rawValue] else { return false }
            lexer.resultSymbol = TokenType.erroneousEndTagName.rawValue
        }
        return true
    }

    private mutating func scanSelfClosingTagDelimiter(_ lexer: inout some ScannerLexer) -> Bool {
        lexer.advance(skip: false)
        guard lexer.lookahead == 0x3E else { return false }
        lexer.advance(skip: false)
        guard !tags.isEmpty else { return false }
        tags.removeLast()
        lexer.resultSymbol = TokenType.selfClosingTagDelimiter.rawValue
        return true
    }

    /// Recognizes a tag, implicit close, raw text, or comment when that token is offered.
    /// - Complexity: O(n + d), where n is the input examined and d is the open-tag depth.
    public mutating func scan(_ lexer: inout some ScannerLexer, validSymbols: [Bool]) -> Bool {
        guard validSymbols.count >= Self.externalNames.count else { return false }
        if validSymbols[TokenType.rawText.rawValue] && !validSymbols[TokenType.startTagName.rawValue]
            && !validSymbols[TokenType.endTagName.rawValue]
        {
            return scanRawText(&lexer)
        }

        while Self.isSpace(lexer.lookahead) { lexer.advance(skip: true) }
        switch lexer.lookahead {
            case 0x3C:  // <
                lexer.markEnd()
                lexer.advance(skip: false)
                if lexer.lookahead == 0x21 {  // !
                    lexer.advance(skip: false)
                    let found = Self.scanComment(&lexer)
                    return validSymbols[TokenType.comment.rawValue] && found
                }
                if validSymbols[TokenType.implicitEndTag.rawValue] {
                    return scanImplicitEndTag(&lexer)
                }
            case 0:
                if validSymbols[TokenType.implicitEndTag.rawValue] {
                    return scanImplicitEndTag(&lexer)
                }
            case 0x2F:  // /
                if validSymbols[TokenType.selfClosingTagDelimiter.rawValue] {
                    return scanSelfClosingTagDelimiter(&lexer)
                }
            default:
                if (validSymbols[TokenType.startTagName.rawValue] || validSymbols[TokenType.endTagName.rawValue])
                    && !validSymbols[TokenType.rawText.rawValue]
                {
                    return validSymbols[TokenType.startTagName.rawValue]
                        ? scanStartTagName(&lexer, validSymbols: validSymbols)
                        : scanEndTagName(&lexer, validSymbols: validSymbols)
                }
        }
        return false
    }
}

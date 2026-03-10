import KittyCodecs
import KittyRenderer
import KittySyntax

func highlightSwift(_ line: String, colorScheme: EditorState.ColorScheme) -> [StyledSpan] {
    let keywords: Set<String> = [
        "import", "struct", "class", "enum", "func", "var", "let", "guard", "if", "else", "switch", "case", "return", "default",
        "final", "extension", "public", "private", "static", "mutating", "override", "init", "deinit", "typealias", "where", "while", "for",
        "in", "do", "catch", "try", "throw", "throws", "as", "is", "self", "nil", "true", "false", "protocol", "associatedtype",
        "internal", "fileprivate", "open", "weak", "unowned", "lazy", "async", "await", "some", "any", "defer", "break", "continue",
        "fallthrough", "repeat", "super", "inout", "convenience", "required", "dynamic", "optional", "indirect", "nonisolated",
        "consuming", "borrowing", "@MainActor", "@Sendable", "@escaping", "@autoclosure", "@discardableResult"
    ]
    let types: Set<String> = [
        "String", "Int", "Bool", "Double", "Float", "Any", "Array", "Dictionary", "Optional", "UInt32", "UInt8", "UInt16", "UInt64",
        "UInt", "Int8", "Int16", "Int32", "Int64", "Date", "Data", "URL", "Error", "Result", "Void", "Never", "Character",
        "Substring", "Set", "ClosedRange", "Range", "Comparable", "Equatable", "Hashable", "Codable", "Decodable", "Encodable",
        "Sendable", "Identifiable", "CustomStringConvertible", "View", "Task", "AsyncStream", "MainActor"
    ]

    let defaultStyle = colorScheme.editorText
    let keywordStyle = colorScheme.syntaxKeyword
    let typeStyle = colorScheme.syntaxType
    let commentStyle = colorScheme.syntaxComment
    let stringStyle = colorScheme.syntaxString
    let numberStyle = colorScheme.syntaxNumber
    let attrStyle = colorScheme.syntaxAttribute

    var spans: [StyledSpan] = []
    var current = ""
    let chars = Array(line)
    var index = 0

    func flushCurrent() {
        guard !current.isEmpty else { return }
        let style: Style
        if current.hasPrefix("@") && keywords.contains(current) {
            style = attrStyle
        } else if keywords.contains(current) {
            style = keywordStyle
        } else if types.contains(current) {
            style = typeStyle
        } else if current.allSatisfy({ $0.isNumber || $0 == "." || $0 == "_" }),
                  let first = current.first,
                  first.isNumber {
            style = numberStyle
        } else {
            style = defaultStyle
        }
        spans.append(StyledSpan(text: current, style: style))
        current = ""
    }

    while index < chars.count {
        let char = chars[index]

        if char == "@" {
            flushCurrent()
            current = "@"
            index += 1
            while index < chars.count && (chars[index].isLetter || chars[index].isNumber || chars[index] == "_") {
                current.append(chars[index])
                index += 1
            }
            flushCurrent()
        } else if char.isWhitespace || "(){}[],.+-*/=<>!&|;:?".contains(char) {
            flushCurrent()
            spans.append(StyledSpan(text: String(char), style: defaultStyle))
            index += 1
        } else if char == "/" && index + 1 < chars.count && chars[index + 1] == "/" {
            flushCurrent()
            spans.append(StyledSpan(text: String(chars[index...]), style: commentStyle))
            return spans
        } else if char == "\"" {
            flushCurrent()
            var stringToken = "\""
            index += 1
            while index < chars.count && chars[index] != "\"" {
                if chars[index] == "\\" && index + 1 < chars.count {
                    stringToken.append(chars[index])
                    stringToken.append(chars[index + 1])
                    index += 2
                } else {
                    stringToken.append(chars[index])
                    index += 1
                }
            }
            if index < chars.count {
                stringToken.append("\"")
                index += 1
            }
            spans.append(StyledSpan(text: stringToken, style: stringStyle))
        } else {
            current.append(char)
            index += 1
        }
    }

    flushCurrent()
    return spans
}

@MainActor
func renderStyledSpans(
    pipeline: RenderPipeline,
    spans: [StyledSpan],
    row: Int,
    col: Int,
    availWidth: Int,
    hScrollOffset: Int,
    isCurrentLine: Bool,
    colorScheme: EditorState.ColorScheme
) {
    var currentCol = col
    var currentX = 0

    for span in spans {
        for char in span.text {
            if currentX >= hScrollOffset && currentX < hScrollOffset + availWidth {
                var style = span.style
                if isCurrentLine {
                    style.bg = colorScheme.editorCursorLine.bg
                }
                pipeline.buffer[row, currentCol] = Cell(character: char, style: style)
                currentCol += 1
            }
            currentX += 1
        }
    }

    while currentCol < col + availWidth {
        let style = isCurrentLine ? colorScheme.editorCursorLine : colorScheme.editorText
        pipeline.buffer[row, currentCol] = Cell(character: " ", style: style)
        currentCol += 1
    }
}

func flattenSpans(_ spans: [StyledSpan]) -> [(Character, Style)] {
    var result: [(Character, Style)] = []
    for span in spans {
        for char in span.text {
            result.append((char, span.style))
        }
    }
    return result
}

extension Character {
    var isPrintable: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return !scalar.isASCII || (scalar.value >= 32 && scalar.value < 127)
    }
}
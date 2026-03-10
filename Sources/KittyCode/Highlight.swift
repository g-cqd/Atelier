import KittyCodecs
import KittyRenderer
import KittySyntax
import KittyText

/// Main highlight entry point — dispatches to grammar-based or regex highlighting.
func highlightLine(_ line: String, language: String?, colorScheme: EditorState.ColorScheme) -> [StyledSpan] {
    switch language {
    case "json":
        return highlightJSON(line, colorScheme: colorScheme)
    case "python":
        return highlightPython(line, colorScheme: colorScheme)
    case "javascript", "typescript":
        return highlightJavaScript(line, colorScheme: colorScheme)
    case "swift":
        return highlightSwift(line, colorScheme: colorScheme)
    default:
        return highlightGeneric(line, colorScheme: colorScheme)
    }
}

// MARK: - Per-language regex-based highlighters

func highlightJSON(_ line: String, colorScheme: EditorState.ColorScheme) -> [StyledSpan] {
    let defaultStyle = colorScheme.editorText
    let keywordStyle = colorScheme.syntaxKeyword
    let stringStyle = colorScheme.syntaxString
    let numberStyle = colorScheme.syntaxNumber

    var spans: [StyledSpan] = []
    let chars = Array(line)
    var index = 0

    while index < chars.count {
        let char = chars[index]

        if char == "\"" {
            // Consume the full quoted string
            var token = "\""
            index += 1
            while index < chars.count && chars[index] != "\"" {
                if chars[index] == "\\" && index + 1 < chars.count {
                    token.append(chars[index])
                    token.append(chars[index + 1])
                    index += 2
                } else {
                    token.append(chars[index])
                    index += 1
                }
            }
            if index < chars.count {
                token.append("\"")
                index += 1
            }
            // Peek past whitespace to see if a colon follows → key
            var peek = index
            while peek < chars.count && chars[peek] == " " { peek += 1 }
            let isKey = peek < chars.count && chars[peek] == ":"
            spans.append(StyledSpan(text: token, style: isKey ? keywordStyle : stringStyle))

        } else if char.isNumber || (char == "-" && index + 1 < chars.count && chars[index + 1].isNumber) {
            var token = String(char)
            index += 1
            while index < chars.count && (chars[index].isNumber || chars[index] == "." || chars[index] == "e"
                    || chars[index] == "E" || chars[index] == "+" || chars[index] == "-") {
                token.append(chars[index])
                index += 1
            }
            spans.append(StyledSpan(text: token, style: numberStyle))

        } else if chars[index...].starts(with: "true".unicodeScalars.map(Character.init))
               || chars[index...].starts(with: "false".unicodeScalars.map(Character.init))
               || chars[index...].starts(with: "null".unicodeScalars.map(Character.init)) {
            let keyword = chars[index...].prefix(while: { $0.isLetter })
            let token = String(keyword)
            spans.append(StyledSpan(text: token, style: keywordStyle))
            index += token.count

        } else {
            spans.append(StyledSpan(text: String(char), style: defaultStyle))
            index += 1
        }
    }

    return spans
}

func highlightPython(_ line: String, colorScheme: EditorState.ColorScheme) -> [StyledSpan] {
    let keywords: Set<String> = [
        "def", "class", "if", "elif", "else", "for", "while", "return",
        "import", "from", "as", "is", "in", "not", "and", "or",
        "with", "try", "except", "finally", "raise", "pass", "break",
        "continue", "yield", "lambda", "global", "nonlocal", "assert",
        "del", "True", "False", "None", "async", "await", "self",
    ]
    let types: Set<String> = [
        "int", "float", "str", "bool", "list", "dict", "tuple",
        "set", "bytes", "type", "object", "range",
    ]

    let defaultStyle = colorScheme.editorText
    let keywordStyle = colorScheme.syntaxKeyword
    let typeStyle = colorScheme.syntaxType
    let commentStyle = colorScheme.syntaxComment
    let stringStyle = colorScheme.syntaxString
    let numberStyle = colorScheme.syntaxNumber

    var spans: [StyledSpan] = []
    let chars = Array(line)
    var index = 0
    var current = ""

    func flushCurrent() {
        guard !current.isEmpty else { return }
        let style: Style
        if keywords.contains(current) {
            style = keywordStyle
        } else if types.contains(current) {
            style = typeStyle
        } else if current.allSatisfy({ $0.isNumber || $0 == "." || $0 == "_" }),
                  let first = current.first, first.isNumber {
            style = numberStyle
        } else {
            style = defaultStyle
        }
        spans.append(StyledSpan(text: current, style: style))
        current = ""
    }

    while index < chars.count {
        let char = chars[index]

        if char == "#" {
            flushCurrent()
            spans.append(StyledSpan(text: String(chars[index...]), style: commentStyle))
            return spans

        } else if char == "\"" || char == "'" {
            flushCurrent()
            let quote = char
            var token = String(char)
            index += 1
            while index < chars.count && chars[index] != quote {
                if chars[index] == "\\" && index + 1 < chars.count {
                    token.append(chars[index])
                    token.append(chars[index + 1])
                    index += 2
                } else {
                    token.append(chars[index])
                    index += 1
                }
            }
            if index < chars.count {
                token.append(chars[index])
                index += 1
            }
            spans.append(StyledSpan(text: token, style: stringStyle))

        } else if char.isLetter || char == "_" {
            current.append(char)
            index += 1

        } else if char.isNumber && current.isEmpty {
            var token = String(char)
            index += 1
            while index < chars.count && (chars[index].isNumber || chars[index] == "." || chars[index] == "_") {
                token.append(chars[index])
                index += 1
            }
            spans.append(StyledSpan(text: token, style: numberStyle))

        } else if char.isWhitespace || "(){}[],.+-*/=<>!&|;:?".contains(char) {
            flushCurrent()
            spans.append(StyledSpan(text: String(char), style: defaultStyle))
            index += 1

        } else {
            flushCurrent()
            spans.append(StyledSpan(text: String(char), style: defaultStyle))
            index += 1
        }
    }

    flushCurrent()
    return spans
}

func highlightJavaScript(_ line: String, colorScheme: EditorState.ColorScheme) -> [StyledSpan] {
    let keywords: Set<String> = [
        "function", "const", "let", "var", "if", "else", "for", "while",
        "return", "class", "new", "this", "import", "export", "from",
        "default", "switch", "case", "break", "continue", "try", "catch",
        "finally", "throw", "typeof", "instanceof", "in", "of", "async",
        "await", "yield", "void", "delete", "extends", "implements",
        "interface", "type", "enum", "abstract", "static", "public",
        "private", "protected", "readonly", "override",
    ]
    let types: Set<String> = [
        "string", "number", "boolean", "any", "void", "never",
        "unknown", "undefined", "null", "Array", "Promise", "Map", "Set",
    ]

    let defaultStyle = colorScheme.editorText
    let keywordStyle = colorScheme.syntaxKeyword
    let typeStyle = colorScheme.syntaxType
    let commentStyle = colorScheme.syntaxComment
    let stringStyle = colorScheme.syntaxString
    let numberStyle = colorScheme.syntaxNumber

    var spans: [StyledSpan] = []
    let chars = Array(line)
    var index = 0
    var current = ""

    func flushCurrent() {
        guard !current.isEmpty else { return }
        let style: Style
        if keywords.contains(current) {
            style = keywordStyle
        } else if types.contains(current) {
            style = typeStyle
        } else if current.allSatisfy({ $0.isNumber || $0 == "." || $0 == "_" }),
                  let first = current.first, first.isNumber {
            style = numberStyle
        } else {
            style = defaultStyle
        }
        spans.append(StyledSpan(text: current, style: style))
        current = ""
    }

    while index < chars.count {
        let char = chars[index]

        // Line comment
        if char == "/" && index + 1 < chars.count && chars[index + 1] == "/" {
            flushCurrent()
            spans.append(StyledSpan(text: String(chars[index...]), style: commentStyle))
            return spans

        // Block comment start (treat rest of line as comment)
        } else if char == "/" && index + 1 < chars.count && chars[index + 1] == "*" {
            flushCurrent()
            spans.append(StyledSpan(text: String(chars[index...]), style: commentStyle))
            return spans

        } else if char == "\"" || char == "'" || char == "`" {
            flushCurrent()
            let quote = char
            var token = String(char)
            index += 1
            while index < chars.count && chars[index] != quote {
                if chars[index] == "\\" && index + 1 < chars.count {
                    token.append(chars[index])
                    token.append(chars[index + 1])
                    index += 2
                } else {
                    token.append(chars[index])
                    index += 1
                }
            }
            if index < chars.count {
                token.append(chars[index])
                index += 1
            }
            spans.append(StyledSpan(text: token, style: stringStyle))

        } else if char.isLetter || char == "_" || char == "$" {
            current.append(char)
            index += 1

        } else if char.isNumber && current.isEmpty {
            var token = String(char)
            index += 1
            while index < chars.count && (chars[index].isNumber || chars[index] == "." || chars[index] == "_") {
                token.append(chars[index])
                index += 1
            }
            spans.append(StyledSpan(text: token, style: numberStyle))

        } else if char.isWhitespace || "(){}[],.+-*/=<>!&|;:?".contains(char) {
            flushCurrent()
            spans.append(StyledSpan(text: String(char), style: defaultStyle))
            index += 1

        } else {
            flushCurrent()
            spans.append(StyledSpan(text: String(char), style: defaultStyle))
            index += 1
        }
    }

    flushCurrent()
    return spans
}

func highlightGeneric(_ line: String, colorScheme: EditorState.ColorScheme) -> [StyledSpan] {
    let defaultStyle = colorScheme.editorText
    let commentStyle = colorScheme.syntaxComment
    let stringStyle = colorScheme.syntaxString
    let numberStyle = colorScheme.syntaxNumber

    var spans: [StyledSpan] = []
    let chars = Array(line)
    var index = 0

    while index < chars.count {
        let char = chars[index]

        // C-style line comment
        if char == "/" && index + 1 < chars.count && chars[index + 1] == "/" {
            spans.append(StyledSpan(text: String(chars[index...]), style: commentStyle))
            return spans

        // Shell/Python-style line comment
        } else if char == "#" {
            spans.append(StyledSpan(text: String(chars[index...]), style: commentStyle))
            return spans

        } else if char == "\"" || char == "'" {
            let quote = char
            var token = String(char)
            index += 1
            while index < chars.count && chars[index] != quote {
                if chars[index] == "\\" && index + 1 < chars.count {
                    token.append(chars[index])
                    token.append(chars[index + 1])
                    index += 2
                } else {
                    token.append(chars[index])
                    index += 1
                }
            }
            if index < chars.count {
                token.append(chars[index])
                index += 1
            }
            spans.append(StyledSpan(text: token, style: stringStyle))

        } else if char.isNumber {
            var token = String(char)
            index += 1
            while index < chars.count && (chars[index].isNumber || chars[index] == ".") {
                token.append(chars[index])
                index += 1
            }
            spans.append(StyledSpan(text: token, style: numberStyle))

        } else {
            spans.append(StyledSpan(text: String(char), style: defaultStyle))
            index += 1
        }
    }

    return spans
}

// MARK: - Swift highlighter

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
            let w = UnicodeWidth.displayWidth(of: char)
            if currentX >= hScrollOffset && currentX + w <= hScrollOffset + availWidth {
                var style = span.style
                if isCurrentLine {
                    style.bg = colorScheme.editorCursorLine.bg
                }
                if w == 2 && currentCol + 1 < col + availWidth {
                    pipeline.buffer[row, currentCol] = Cell(character: char, style: style, width: 2)
                    pipeline.buffer[row, currentCol + 1] = Cell(character: "\0", style: style, width: 0)
                    currentCol += 2
                } else if w == 1 {
                    pipeline.buffer[row, currentCol] = Cell(character: char, style: style)
                    currentCol += 1
                }
            }
            currentX += w
        }
    }

    while currentCol < col + availWidth {
        let style = isCurrentLine ? colorScheme.editorCursorLine : colorScheme.editorText
        pipeline.buffer[row, currentCol] = Cell(character: " ", style: style)
        currentCol += 1
    }
}

/// Converts a character index within a line to the display column offset,
/// accounting for wide characters.
func displayColumn(for charIndex: Int, in line: String) -> Int {
    var col = 0
    for (i, char) in line.enumerated() {
        if i >= charIndex { break }
        col += UnicodeWidth.displayWidth(of: char)
    }
    return col
}

/// Converts a display column offset to the character index, accounting for wide characters.
func charIndex(forDisplayColumn targetCol: Int, in line: String) -> Int {
    var col = 0
    for (i, char) in line.enumerated() {
        if col >= targetCol { return i }
        col += UnicodeWidth.displayWidth(of: char)
    }
    return line.count
}

extension Character {
    var isPrintable: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return !scalar.isASCII || (scalar.value >= 32 && scalar.value < 127)
    }
}
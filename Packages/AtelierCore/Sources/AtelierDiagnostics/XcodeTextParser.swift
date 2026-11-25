public import Foundation

/// Parses the "path:line:col: severity: message" lines a tool emits on stderr in Xcode's diagnostic text format.
public enum XcodeTextParser {
    /// Parses every matching line of `text`, with paths made relative to `root` under any of its spellings (see
    /// ``RootRelativePath``); lines that do not fit the format are ignored.
    public static func findings(from text: String, tool: DiagnosticTool, root: URL) -> [Finding] {
        let paths = RootRelativePath(root: root)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap {
                finding(from: String($0), tool: tool, paths: paths)
            }
    }

    private static let severities: [String: Finding.Severity] = [
        "error": .error, "warning": .warning, "note": .note
    ]

    private static func finding(from line: String, tool: DiagnosticTool, paths: RootRelativePath) -> Finding? {
        // Scan for ":<digits>:<digits>: <severity>: " starting after the path, since the path itself may contain
        // colons on some filesystems but never digit-colon-digit-colon in the middle of a component.
        let scalars = Array(line)
        var index = 0
        var lineNumberStart: Int?
        while index < scalars.count {
            if scalars[index] == ":", let lineStart = matchLineNumber(scalars, from: index) {
                lineNumberStart = lineStart
                break
            }
            index += 1
        }
        guard let markerStart = lineNumberStart else { return nil }
        let path = String(scalars[0 ..< markerStart])
        guard !path.isEmpty else { return nil }

        let rest = String(scalars[(markerStart + 1)...])
        let fields = rest.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
        guard fields.count >= 4, let lineNumber = Int(fields[0]), let column = Int(fields[1]) else { return nil }
        let severityToken = fields[2].trimmingCharacters(in: .whitespaces)
        guard let severity = severities[severityToken] else { return nil }
        var message = String(fields[3]).trimmingCharacters(in: .whitespaces)

        // swift-format leads a message with `[RuleName]`, Lockwood's swiftformat with `(ruleName)`; either becomes
        // the rule ID and leaves the message.
        var ruleID = tool.rawValue
        if message.hasPrefix("["), let closing = message.firstIndex(of: "]") {
            ruleID = String(message[message.index(after: message.startIndex) ..< closing])
            message = String(message[message.index(after: closing)...]).trimmingCharacters(in: .whitespaces)
        } else if message.hasPrefix("("), let closing = message.firstIndex(of: ")") {
            ruleID = String(message[message.index(after: message.startIndex) ..< closing])
            message = String(message[message.index(after: closing)...]).trimmingCharacters(in: .whitespaces)
        }

        return Finding(
            tool: tool,
            ruleID: ruleID,
            message: message,
            file: paths.relativePath(of: path),
            line: lineNumber,
            column: column,
            severity: severity
        )
    }

    /// `colon` when it starts a `:<digits>:` run, else nil.
    private static func matchLineNumber(_ scalars: [Character], from colon: Int) -> Int? {
        var index = colon + 1
        var sawDigit = false
        while index < scalars.count, scalars[index].isNumber {
            sawDigit = true
            index += 1
        }
        guard sawDigit, index < scalars.count, scalars[index] == ":" else { return nil }
        return colon
    }
}

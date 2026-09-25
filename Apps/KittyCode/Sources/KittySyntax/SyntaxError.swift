public enum SyntaxError: Error, Sendable, Equatable {
    case unsupportedLanguage(String)
    case grammarLoadFailed(String)
    case queryLoadFailed(String)
    case highlightingFailed(String)
}

/// Where grammar resources are loaded from.
public enum GrammarSource: Sendable, Equatable, Codable {
    case bundled
    case repository(owner: String, repo: String, ref: String)
}

/// Codable manifest describing grammar resources for a language.
public struct GrammarResourceManifest: Sendable, Equatable, Codable {
    public let language: String
    public let source: GrammarSource
    public let grammarPath: String
    public let queryPath: String

    public init(
        language: String,
        source: GrammarSource = .bundled,
        grammarPath: String = "grammar.json",
        queryPath: String = "highlights.scm"
    ) {
        self.language = language
        self.source = source
        self.grammarPath = grammarPath
        self.queryPath = queryPath
    }
}

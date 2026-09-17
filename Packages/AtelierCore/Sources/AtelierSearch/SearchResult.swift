public struct SearchFileResult: Sendable {
    public var filePath: String
    public var fileName: String
    public var matches: [SearchMatch]
    public var contextSnippets: [String]

    public init(
        filePath: String, fileName: String, matches: [SearchMatch], contextSnippets: [String]
    ) {
        self.filePath = filePath
        self.fileName = fileName
        self.matches = matches
        self.contextSnippets = contextSnippets
    }
}

public struct SearchRunResult: Sendable {
    public var query: SearchQuery
    public var results: [SearchFileResult]
    public var totalMatchCount: Int
    public var filesSearched: Int
    public var filesMatched: Int
    public var durationMilliseconds: Double
    public var wasCancelled: Bool

    public init(
        query: SearchQuery,
        results: [SearchFileResult],
        totalMatchCount: Int,
        filesSearched: Int,
        filesMatched: Int,
        durationMilliseconds: Double,
        wasCancelled: Bool
    ) {
        self.query = query
        self.results = results
        self.totalMatchCount = totalMatchCount
        self.filesSearched = filesSearched
        self.filesMatched = filesMatched
        self.durationMilliseconds = durationMilliseconds
        self.wasCancelled = wasCancelled
    }
}

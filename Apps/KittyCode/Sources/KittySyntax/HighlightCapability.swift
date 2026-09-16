/// The tier of highlighting a language achieves.
public enum HighlightTier: Int, Sendable, Comparable, Hashable {
    case plain = 0       // no highlighting
    case lexical = 1     // keyword/string/comment fallback only
    case structural = 2  // tree-sitter grammar, basic queries
    case enhanced = 3    // external scanners, full queries
    case semantic = 4    // LSP semantic tokens merged

    public static func < (lhs: HighlightTier, rhs: HighlightTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Query features a grammar's query file may require.
public enum QueryFeature: String, Sendable, Hashable, Codable {
    case predicates
    case quantifiers
    case multipleCaptures
    case fieldNames
    case alternations
    case anchors
}

/// What a grammar needs from the host parser.
public struct ParserRequirements: Sendable, Equatable {
    public let needsExternalScanner: Bool
    public let externalSymbolCount: Int
    public let queryFeatures: Set<QueryFeature>

    public init(
        needsExternalScanner: Bool = false,
        externalSymbolCount: Int = 0,
        queryFeatures: Set<QueryFeature> = []
    ) {
        self.needsExternalScanner = needsExternalScanner
        self.externalSymbolCount = externalSymbolCount
        self.queryFeatures = queryFeatures
    }
}

/// What the host parser currently supports.
public struct HostCapabilities: Sendable, Equatable {
    public let supportsExternalScanner: Bool
    public let supportedQueryFeatures: Set<QueryFeature>

    public init(
        supportsExternalScanner: Bool = false,
        supportedQueryFeatures: Set<QueryFeature> = [
            .predicates, .fieldNames, .alternations, .anchors,
            .quantifiers, .multipleCaptures,
        ]
    ) {
        self.supportsExternalScanner = supportsExternalScanner
        self.supportedQueryFeatures = supportedQueryFeatures
    }
}

/// Report on what highlighting tier a language achieves and what blocks improvement.
public struct HighlightCapabilityReport: Sendable, Equatable {
    public let language: String
    public let achievedTier: HighlightTier
    public let maxPossibleTier: HighlightTier
    public let blockers: [String]

    public init(
        language: String,
        achievedTier: HighlightTier,
        maxPossibleTier: HighlightTier,
        blockers: [String] = []
    ) {
        self.language = language
        self.achievedTier = achievedTier
        self.maxPossibleTier = maxPossibleTier
        self.blockers = blockers
    }
}

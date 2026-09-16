public import AtelierSyntaxModel

/// How a language detects its files.
public struct DetectionContribution: Sendable, Equatable {
    public let extensions: [String]
    public let filenames: [String]

    public init(extensions: [String], filenames: [String] = []) {
        self.extensions = extensions
        self.filenames = filenames
    }
}

/// Where the lexical provider comes from.
public enum LexicalProviderDescriptor: Sendable, Equatable {
    case builtin
    case custom(name: String)
}

/// Where the structural provider comes from.
public enum StructuralProviderDescriptor: Sendable, Equatable {
    case grammar(needsExternalScanner: Bool)
    case none
}

/// Where the semantic provider comes from.
public enum SemanticProviderDescriptor: Sendable, Equatable {
    case lsp
    case none
}

/// Strategy for merging highlight layers.
public enum HighlightMergeStrategy: Sendable, Equatable {
    case standard
    case structuralOnly
    case semanticOnly
}

/// What highlighting features are available for a language.
public struct HighlightingCapabilities: Sendable, Equatable {
    public let achievedTier: HighlightTier
    public let queryFeatures: Set<QueryFeature>

    public init(achievedTier: HighlightTier, queryFeatures: Set<QueryFeature> = []) {
        self.achievedTier = achievedTier
        self.queryFeatures = queryFeatures
    }
}

/// Declares everything needed to highlight a language.
public struct LanguageHighlightingContribution: Sendable, Equatable {
    public let languageName: String
    public let detection: DetectionContribution
    public let lexical: LexicalProviderDescriptor
    public let structural: StructuralProviderDescriptor
    public let semantic: SemanticProviderDescriptor
    public let mergeStrategy: HighlightMergeStrategy
    public let capabilities: HighlightingCapabilities

    public init(
        languageName: String,
        detection: DetectionContribution,
        lexical: LexicalProviderDescriptor = .builtin,
        structural: StructuralProviderDescriptor = .none,
        semantic: SemanticProviderDescriptor = .none,
        mergeStrategy: HighlightMergeStrategy = .standard,
        capabilities: HighlightingCapabilities = HighlightingCapabilities(achievedTier: .plain)
    ) {
        self.languageName = languageName
        self.detection = detection
        self.lexical = lexical
        self.structural = structural
        self.semantic = semantic
        self.mergeStrategy = mergeStrategy
        self.capabilities = capabilities
    }

    /// Generate a contribution from a bundled language manifest entry and capability report.
    static func fromBundled(
        entry: BundledLanguageEntry,
        report: HighlightCapabilityReport
    ) -> LanguageHighlightingContribution {
        let detection = DetectionContribution(extensions: entry.extensions)

        let structural: StructuralProviderDescriptor
        if report.achievedTier >= .structural {
            structural = .grammar(needsExternalScanner: false)
        } else if report.maxPossibleTier >= .enhanced {
            structural = .grammar(needsExternalScanner: true)
        } else {
            structural = .none
        }

        let capabilities = HighlightingCapabilities(
            achievedTier: report.achievedTier
        )

        return LanguageHighlightingContribution(
            languageName: entry.name,
            detection: detection,
            lexical: .builtin,
            structural: structural,
            semantic: .none,
            mergeStrategy: .standard,
            capabilities: capabilities
        )
    }
}

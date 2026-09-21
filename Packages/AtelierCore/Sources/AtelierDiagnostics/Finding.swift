/// One diagnostic reported by a tool, anchored at a location in an analyzed file.
public struct Finding: Sendable, Hashable, Codable {
    /// How serious a finding is, ordered from least to most severe.
    public enum Severity: String, Sendable, Codable, CaseIterable, Comparable {
        case note
        case warning
        case error

        /// This severity's position in the note-warning-error ordering.
        private var rank: Int {
            switch self {
                case .note: 0
                case .warning: 1
                case .error: 2
            }
        }

        public static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs.rank < rhs.rank
        }
    }

    public let tool: DiagnosticTool
    public let ruleID: String
    public let message: String
    /// Analysis-root-relative, `/`-separated path to the file the finding is anchored at.
    public let file: String
    /// 1-based line the finding starts at.
    public let line: Int
    public let column: Int?
    public let endLine: Int?
    public let endColumn: Int?
    public let severity: Severity
    public let related: [RelatedLocation]

    public init(
        tool: DiagnosticTool,
        ruleID: String,
        message: String,
        file: String,
        line: Int,
        column: Int? = nil,
        endLine: Int? = nil,
        endColumn: Int? = nil,
        severity: Severity,
        related: [RelatedLocation] = []
    ) {
        self.tool = tool
        self.ruleID = ruleID
        self.message = message
        self.file = file
        self.line = line
        self.column = column
        self.endLine = endLine
        self.endColumn = endColumn
        self.severity = severity
        self.related = related
    }
}

/// A secondary location a finding points to, such as the other end of a duplicate or a definition site.
public struct RelatedLocation: Sendable, Hashable, Codable {
    public let file: String
    public let line: Int
    public let message: String?

    public init(file: String, line: Int, message: String? = nil) {
        self.file = file
        self.line = line
        self.message = message
    }
}

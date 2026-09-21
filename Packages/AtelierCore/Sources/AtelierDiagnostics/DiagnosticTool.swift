/// A static-analysis tool the diagnostics engine can discover, run and parse the output of.
public enum DiagnosticTool: String, CaseIterable, Sendable, Codable, Identifiable {
    case swiftlint
    case swiftFormat = "swift-format"
    /// Nick Lockwood's SwiftFormat (github.com/nicklockwood/SwiftFormat), distinct from Apple's ``swiftFormat``:
    /// a different binary, a different configuration file (`.swiftformat`), and a different rule set. Some
    /// projects adopt this one instead of Apple's, so both are offered as independent tools.
    case swiftformat
    case arcleak
    case dolly
    case deadwood

    public var id: String { rawValue }

    /// The name looked up on disk; matches the raw value except where the binary differs from it.
    public var executableName: String {
        switch self {
            case .swiftlint: "swiftlint"
            case .swiftFormat: "swift-format"
            case .swiftformat: "swiftformat"
            case .arcleak: "arcleak"
            case .dolly: "dolly"
            case .deadwood: "deadwood"
        }
    }

    /// The name shown in UI. Apple's and Lockwood's formatters share a name closely enough (`swift-format` vs
    /// `swiftformat`) that the Tools tab spells the second out fully, with its author, to keep the two
    /// unambiguous at a glance.
    public var displayName: String {
        switch self {
            case .swiftlint: "SwiftLint"
            case .swiftFormat: "swift-format"
            case .swiftformat: "SwiftFormat (Lockwood)"
            case .arcleak: "arcleak"
            case .dolly: "dolly"
            case .deadwood: "deadwood"
        }
    }

    /// The environment variable that, when it names an executable, wins over every search path for this tool.
    public var overrideVariable: String {
        switch self {
            case .swiftlint: "GDV_SWIFTLINT"
            case .swiftFormat: "GDV_SWIFT_FORMAT"
            case .swiftformat: "GDV_SWIFTFORMAT"
            case .arcleak: "GDV_ARCLEAK"
            case .dolly: "GDV_DOLLY"
            case .deadwood: "GDV_DEADWOOD"
        }
    }

    /// How the tool analyzes its input: per file, or over the whole corpus at once.
    public enum AnalysisScope: Sendable, Equatable {
        case perFile
        case corpus
    }

    public var scope: AnalysisScope {
        switch self {
            case .swiftFormat, .arcleak: .perFile
            case .swiftlint, .swiftformat, .dolly, .deadwood: .corpus
        }
    }

    /// The shape the tool's output is parsed as.
    public enum ToolOutputFormat: Sendable, Equatable {
        case sarif
        case xcodeTextOnStderr
    }

    public var outputFormat: ToolOutputFormat {
        switch self {
            case .swiftFormat, .swiftformat: .xcodeTextOnStderr
            case .swiftlint, .arcleak, .dolly, .deadwood: .sarif
        }
    }

    /// Configuration file names the tool reads from a project root, in the order it looks for them.
    public var configFileNames: [String] {
        switch self {
            case .swiftlint: [".swiftlint.yml"]
            case .swiftFormat: [".swift-format"]
            case .swiftformat: [".swiftformat"]
            case .arcleak: [".arcleak.yml", ".arcleak-baseline.json"]
            case .dolly: [".dolly.yml"]
            case .deadwood: [".deadwood.yml"]
        }
    }

    /// True when the tool ships inside the Swift toolchain rather than needing a separate install.
    public var isInToolchain: Bool {
        self == .swiftFormat
    }

    /// The configuration file name whose absence at the analyzed root means the tool has not been adopted by the
    /// project, so ``DiagnosticsEngine`` skips running it there rather than reporting findings from a config the
    /// project never opted into. `nil` for a tool that is still useful without a project-specific configuration
    /// (swiftlint's curated defaults, for instance) or that has no dedicated configuration file of its own.
    public var requiredConfigurationFile: String? {
        switch self {
            case .swiftFormat: ".swift-format"
            case .swiftformat: ".swiftformat"
            case .swiftlint, .arcleak, .dolly, .deadwood: nil
        }
    }
}

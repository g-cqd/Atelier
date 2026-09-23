/// A static-analysis tool the diagnostics engine can discover, run and parse the output of.
public enum DiagnosticTool: String, CaseIterable, Sendable, Codable, Identifiable {
    case swiftlint
    case swiftFormat = "swift-format"
    /// Nick Lockwood's SwiftFormat: a separate tool from Apple's ``swiftFormat``, with its own binary and config.
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

    /// The name shown in UI; Lockwood's formatter carries its author's name to tell it apart from Apple's.
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

    /// The configuration file a project must have at the analyzed root for ``DiagnosticsEngine`` to run the tool
    /// there; `nil` when the tool runs without one.
    public var requiredConfigurationFile: String? {
        switch self {
            case .swiftFormat: ".swift-format"
            case .swiftformat: ".swiftformat"
            case .swiftlint, .arcleak, .dolly, .deadwood: nil
        }
    }
}

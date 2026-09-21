public import Foundation

/// A user's per-tool override: whether the tool runs at all, and where to look for it before any
/// search path is consulted.
public struct ToolLocation: Sendable, Codable, Equatable {
    public var isEnabled: Bool
    /// A path to the executable that wins over every search rung but an environment override.
    /// Held as a plain `String` rather than a typed path so this value stays trivially `Codable`
    /// without adding `SystemPackage` to this target's public surface.
    public var customPath: String?
    /// Reserved for a security-scoped bookmark when the app sandboxes; unused today.
    public var bookmark: Data?

    public init(isEnabled: Bool = true, customPath: String? = nil, bookmark: Data? = nil) {
        self.isEnabled = isEnabled
        self.customPath = customPath
        self.bookmark = bookmark
    }
}

/// Which search rung located a tool's executable.
public enum ToolOrigin: String, Sendable, Codable, Equatable {
    case environment
    case custom
    case bundled
    case toolchain
    case wellKnown
    case shellPath
}

/// A tool's discovered location and version, or the lack of one.
public struct ToolStatus: Sendable, Equatable {
    public let tool: DiagnosticTool
    public let url: URL?
    public let origin: ToolOrigin?
    public let version: String?

    /// True once an executable was located, whether or not its version could be probed.
    public var isAvailable: Bool { url != nil }

    public init(tool: DiagnosticTool, url: URL?, origin: ToolOrigin?, version: String?) {
        self.tool = tool
        self.url = url
        self.origin = origin
        self.version = version
    }
}

public import Foundation

/// Finds a tool on disk once, in a fixed order, so no `PATH` lookup happens per run and a shim cannot shadow it. Only
/// absolute paths are used: a relative one would resolve against the process's working directory, which can be a
/// repository under review.
public struct ExecutableResolver: Sendable {
    /// An environment variable naming, by absolute path, an executable that wins over every search path.
    public var overrideVariable: String?
    /// Directories searched in order after the override; `$PATH` is consulted first when `searchesPath` is set.
    public var searchPaths: [String]
    public var searchesPath: Bool
    /// Directories never used even when they are on `$PATH`, such as `/usr/bin` on macOS where `git` is a shim
    /// that re-resolves the developer directory on every launch.
    public var excludedPaths: Set<String>
    /// The directory used when nothing else has the tool.
    public var fallbackPath: String

    public init(
        overrideVariable: String? = nil,
        searchPaths: [String] = [],
        searchesPath: Bool = true,
        excludedPaths: Set<String> = [],
        fallbackPath: String = "/usr/bin"
    ) {
        self.overrideVariable = overrideVariable
        self.searchPaths = searchPaths
        self.searchesPath = searchesPath
        self.excludedPaths = excludedPaths
        self.fallbackPath = fallbackPath
    }

    /// The first executable named `name` in the resolver's order, or the fallback path whether or not it exists. A
    /// relative override value or directory, from `$PATH` or ``searchPaths``, is skipped.
    /// - Complexity: O(directories) file system checks.
    public func resolve(_ name: String, environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        let fileManager = FileManager.default
        if let variable = overrideVariable, let override = environment[variable], override.hasPrefix("/"),
            fileManager.isExecutableFile(atPath: override)
        {
            return URL(filePath: override)
        }
        var directories: [String] = []
        if searchesPath {
            directories += (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        }
        directories += searchPaths
        for directory in directories where directory.hasPrefix("/") && !excludedPaths.contains(directory) {
            let candidate = directory + "/" + name
            if fileManager.isExecutableFile(atPath: candidate) { return URL(filePath: candidate) }
        }
        return URL(filePath: fallbackPath + "/" + name)
    }
}

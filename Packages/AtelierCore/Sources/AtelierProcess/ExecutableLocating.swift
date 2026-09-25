public import Foundation

/// An executable to look for: its names, and the user's and the tool's own hints for where it is.
public struct ExecutableQuery: Sendable, Equatable {
    /// The executable's names, most preferred first: a name found anywhere wins over every later one.
    public var names: [String]
    /// An environment variable naming, by absolute path, an executable that wins over every search.
    public var overrideVariable: String?
    /// A path the user chose, which wins over every search but the environment override.
    public var customPath: String?
    /// Whether the active Xcode toolchain is asked for the executable.
    public var searchesToolchain: Bool
    /// Directories under the user's home, such as `go/bin`, searched after the usual install locations.
    public var homeRelativeDirectories: [String]

    public init(
        names: [String], overrideVariable: String? = nil, customPath: String? = nil, searchesToolchain: Bool = false,
        homeRelativeDirectories: [String] = []
    ) {
        self.names = names
        self.overrideVariable = overrideVariable
        self.customPath = customPath
        self.searchesToolchain = searchesToolchain
        self.homeRelativeDirectories = homeRelativeDirectories
    }
}

/// Finds executables on disk, so that a client of one, such as a language server session, needs no discovery code of
/// its own.
public protocol ExecutableLocating: Sendable {
    /// The executable `query` describes; nil when none of its names is found.
    func locateExecutable(_ query: ExecutableQuery) async -> URL?
}

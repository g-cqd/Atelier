public import AtelierProcess
public import Foundation

/// Locates diagnostic tools, and executables searched the same way such as `sourcekit-lsp`, in a fixed precedence,
/// and probes their version. `xcrun` answers, the login shell's `$PATH` and versions are cached until
/// ``invalidate()``, a version only while its executable's modification date holds.
public actor ToolDiscovery {
    private let runner: any ProcessRunner
    private let bundledDirectory: URL?
    private let homeDirectory: URL
    private let environment: [String: String]
    private let fileManager: FileManager

    /// `.some(nil)` caches a name `xcrun` could not find; an absent key has never been probed.
    private var xcrunCache: [String: URL?] = [:]
    /// nil until the login shell's `$PATH` has been probed once; an empty array is a valid, cached result.
    private var shellPathDirectoriesCache: [String]?
    private var versionCache: [String: (mtime: Date?, version: String?)] = [:]

    public init(
        runner: any ProcessRunner,
        bundledDirectory: URL?,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) {
        self.runner = runner
        self.bundledDirectory = bundledDirectory
        self.homeDirectory = homeDirectory
        self.environment = environment
        self.fileManager = fileManager
    }

    /// The directories always searched after the override, the custom path, the bundle and the toolchain, and
    /// before the login shell's `$PATH`.
    private var wellKnownDirectories: [String] {
        [
            "/opt/homebrew/bin", "/usr/local/bin",
            homeDirectory.appending(path: ".swiftly/bin").path,
            homeDirectory.appending(path: ".mint/bin").path,
            homeDirectory.appending(path: ".local/bin").path
        ]
    }

    /// Locates `executableName` by the shared precedence: an environment override, a custom path, the app's
    /// bundled copy, (optionally) the active toolchain, a fixed list of well-known install directories, then the
    /// login shell's `$PATH`. The first executable file found wins.
    public func locate(
        executableName: String, overrideVariable: String?, customPath: String?, searchesToolchain: Bool
    ) async -> (url: URL, origin: ToolOrigin)? {
        if let overrideVariable, let override = environment[overrideVariable], isExecutable(override) {
            return (URL(filePath: override), .environment)
        }
        if let customPath, isExecutable(customPath) {
            return (URL(filePath: customPath), .custom)
        }
        if let bundledDirectory {
            let candidate = bundledDirectory.appending(path: executableName)
            if isExecutable(candidate.path) { return (candidate, .bundled) }
        }
        if searchesToolchain, let url = await xcrunFind(executableName) {
            return (url, .toolchain)
        }
        let wellKnown = wellKnownDirectories
        for directory in wellKnown {
            let candidate = directory + "/" + executableName
            if isExecutable(candidate) { return (URL(filePath: candidate), .wellKnown) }
        }
        for directory in await shellPathDirectories() where !wellKnown.contains(directory) {
            let candidate = directory + "/" + executableName
            if isExecutable(candidate) { return (URL(filePath: candidate), .shellPath) }
        }
        return nil
    }

    /// Locates `tool`, honoring `location`'s enable flag and custom path when given. Returns nil when the tool is
    /// disabled or could not be found anywhere in the precedence.
    public func locate(_ tool: DiagnosticTool, location: ToolLocation?) async -> (url: URL, origin: ToolOrigin)? {
        if let location, !location.isEnabled { return nil }
        return await locate(
            executableName: tool.executableName, overrideVariable: tool.overrideVariable,
            customPath: location?.customPath, searchesToolchain: tool.isInToolchain
        )
    }

    /// `tool`'s location and version, both nil when it could not be found.
    public func status(_ tool: DiagnosticTool, location: ToolLocation?) async -> ToolStatus {
        guard let located = await locate(tool, location: location) else {
            return ToolStatus(tool: tool, url: nil, origin: nil, version: nil)
        }
        let version = await probeVersion(tool: tool, url: located.url)
        return ToolStatus(tool: tool, url: located.url, origin: located.origin, version: version)
    }

    /// Drops every cache: the next lookup re-probes `xcrun`, the login shell's `$PATH`, and every tool's version.
    public func invalidate() {
        xcrunCache.removeAll()
        shellPathDirectoriesCache = nil
        versionCache.removeAll()
    }

    // MARK: - xcrun

    private func xcrunFind(_ name: String) async -> URL? {
        if let cached = xcrunCache[name] { return cached }
        let spec = ProcessSpec(
            executable: URL(filePath: "/usr/bin/xcrun"), arguments: ["--find", name], timeout: .seconds(10))
        let found: URL?
        do {
            let output = try await runner.run(spec)
            if output.succeeded {
                let path = String(decoding: output.standardOutput, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                found = path.isEmpty ? nil : URL(filePath: path)
            } else {
                found = nil
            }
        } catch {
            found = nil
        }
        xcrunCache[name] = found
        return found
    }

    // MARK: - Login shell $PATH

    private func shellPathDirectories() async -> [String] {
        if let cached = shellPathDirectoriesCache { return cached }
        let shell = environment["SHELL"] ?? "/bin/zsh"
        let spec = ProcessSpec(
            executable: URL(filePath: shell), arguments: ["-l", "-c", "echo $PATH"], timeout: .seconds(5))
        var directories: [String] = []
        do {
            let output = try await runner.run(spec)
            if output.succeeded {
                let text = String(decoding: output.standardOutput, as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                directories = text.split(separator: ":").map(String.init)
            }
        } catch {
            // Left empty: a shell that cannot be run leaves the rung with nothing to offer.
        }
        shellPathDirectoriesCache = directories
        return directories
    }

    // MARK: - Version probe

    private func probeVersion(tool: DiagnosticTool, url: URL) async -> String? {
        let mtime = modificationDate(ofItemAt: url.path)
        let key = url.path
        if let cached = versionCache[key], cached.mtime == mtime { return cached.version }
        let spec = ProcessSpec(executable: url, arguments: ToolCommand.version(tool), timeout: .seconds(10))
        var version: String?
        do {
            let output = try await runner.run(spec)
            let text = String(decoding: output.standardOutput, as: UTF8.self)
            let firstLine = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            version = (firstLine?.isEmpty ?? true) ? nil : firstLine
        } catch {
            version = nil
        }
        versionCache[key] = (mtime: mtime, version: version)
        return version
    }

    private func modificationDate(ofItemAt path: String) -> Date? {
        (try? fileManager.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    private func isExecutable(_ path: String) -> Bool {
        fileManager.isExecutableFile(atPath: path)
    }
}

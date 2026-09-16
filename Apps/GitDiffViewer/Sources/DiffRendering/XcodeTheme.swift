package import AtelierTheme
import DiffCore
package import DiffGit
package import Foundation

/// Themes installed for Xcode: the user's own, then the ones bundled with the selected Xcode.
package enum XcodeThemeLibrary {
    package struct Entry: Identifiable, Hashable, Sendable {
        package let name: String
        package let url: URL

        package var id: String { url.path(percentEncoded: false) }
    }

    /// The user's themes, then the ones bundled with the Xcode `xcode-select` points at; `xcode-select` runs
    /// through `runner`, so the listing never blocks a thread and a test can script it.
    package static func entries(runner: any ProcessRunner) async -> [Entry] {
        let user = URL.libraryDirectory.appending(path: "Developer/Xcode/UserData/FontAndColorThemes")
        let bundled = await developerDirectory(runner: runner)
            .map {
                $0.appending(
                    path: "../SharedFrameworks/DVTUserInterfaceKit.framework/Versions/A/Resources/FontAndColorThemes")
            }
        return ([user] + (bundled.map { [$0] } ?? [])).flatMap(entries(in:))
    }

    package static func theme(at path: String) -> SyntaxTheme? {
        (try? XcodeThemeDocument(contentsOf: URL(filePath: path)))?
            .syntaxTheme(named: URL(filePath: path).deletingPathExtension().lastPathComponent)
    }

    private static func entries(in directory: URL) -> [Entry] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return
            urls
            .filter { $0.pathExtension == "xccolortheme" }
            .map { Entry(name: $0.deletingPathExtension().lastPathComponent, url: $0.standardizedFileURL) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The selected developer directory, or nil when `xcode-select` fails or names nothing.
    private static func developerDirectory(runner: any ProcessRunner) async -> URL? {
        let spec = ProcessSpec(executable: URL(filePath: "/usr/bin/xcode-select"), arguments: ["-p"])
        guard let output = try? await runner.run(spec), output.succeeded else { return nil }
        let path = String(decoding: output.standardOutput, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : URL(filePath: path, directoryHint: .isDirectory)
    }
}

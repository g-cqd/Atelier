package import AtelierTheme
import DiffCore
import DiffGit
package import Foundation

/// Themes installed for Xcode: the user's own, then the ones bundled with the selected Xcode.
package enum XcodeThemeLibrary {
    package struct Entry: Identifiable, Hashable, Sendable {
        package let name: String
        package let url: URL

        package var id: String { url.path(percentEncoded: false) }
    }

    package static func entries() -> [Entry] {
        let user = URL.libraryDirectory.appending(path: "Developer/Xcode/UserData/FontAndColorThemes")
        let bundled = developerDirectory.map {
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

    /// Resolved once: `xcode-select` is a process launch.
    private static let developerDirectory: URL? = {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/xcode-select")
        process.arguments = ["-p"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : URL(filePath: path, directoryHint: .isDirectory)
    }()
}

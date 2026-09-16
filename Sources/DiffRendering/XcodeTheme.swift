package import AppKit
import DiffCore
import DiffGit
package import Foundation

/// The parts of an Xcode `.xccolortheme` file the viewer uses.
/// Fonts and colors are immutable, which keeps the value safe to share.
package struct XcodeTheme: @unchecked Sendable {
    package let background: NSColor?
    package let selection: NSColor?
    package let plainFont: NSFont?
    /// Xcode's line spacing, a multiple of the font's line height.
    package let lineHeightMultiple: Double?
    private let colors: [String: NSColor]

    package init(data: Data) throws {
        let file = try PropertyListDecoder().decode(File.self, from: data)
        background = file.background.flatMap(Self.color(from:))
        selection = file.selection.flatMap(Self.color(from:))
        lineHeightMultiple = file.lineSpacing
        colors = (file.colors ?? [:]).compactMapValues(Self.color(from:))
        plainFont = file.fonts?["xcode.syntax.plain"].flatMap(Self.font(from:))
    }

    package init(contentsOf url: URL) throws {
        try self.init(data: Data(contentsOf: url))
    }

    package func color(for key: String) -> NSColor? {
        colors[key]
    }

    /// Parses Xcode's "red green blue alpha" components, in sRGB.
    package static func color(from value: String) -> NSColor? {
        let components = value.split(separator: " ").compactMap { Double($0) }
        guard components.count == 4 else { return nil }
        return NSColor(srgbRed: components[0], green: components[1], blue: components[2], alpha: components[3])
    }

    /// Parses Xcode's "PostScriptName - size".
    package static func font(from value: String) -> NSFont? {
        let parts = value.components(separatedBy: " - ")
        guard parts.count == 2, let size = Double(parts[1]) else { return nil }
        return NSFont(name: parts[0], size: size)
    }

    private struct File: Decodable {
        let background: String?
        let selection: String?
        let lineSpacing: Double?
        let colors: [String: String]?
        let fonts: [String: String]?

        enum CodingKeys: String, CodingKey {
            case background = "DVTSourceTextBackground"
            case selection = "DVTSourceTextSelectionColor"
            case lineSpacing = "DVTLineSpacing"
            case colors = "DVTSourceTextSyntaxColors"
            case fonts = "DVTSourceTextSyntaxFonts"
        }
    }
}

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

    package static func theme(at path: String) -> XcodeTheme? {
        try? XcodeTheme(contentsOf: URL(filePath: path))
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

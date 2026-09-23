public import AtelierProcess
import Darwin
import Foundation
import os

/// The Apple platform whose SDK the SDK tier resolves a file's symbols against.
public enum SDKPlatform: String, Sendable, Hashable, CaseIterable {
    /// The Mac's SDK, which sourcekit-lsp uses when given none.
    case macOS
    /// The iOS simulator's SDK, which holds UIKit and the other frameworks iOS alone has.
    case iOS

    /// `xcrun`'s name for the platform's SDK.
    public var sdkName: String {
        switch self {
            case .macOS: "macosx"
            case .iOS: "iphonesimulator"
        }
    }

    /// The modules a probe imports besides the file's own, so that a symbol the file reaches through a module it does
    /// not import itself, as UIKit's through SwiftUI, still resolves.
    var defaultImports: [String] {
        switch self {
            case .macOS: ["AppKit", "Foundation", "SwiftUI"]
            case .iOS: ["Foundation", "SwiftUI", "UIKit"]
        }
    }

    /// Frameworks this platform's SDK has and the other's lacks, among those an app imports: a file that imports one
    /// belongs to this platform. Taken from the frameworks of the macOS and iOS simulator 26.5 SDKs.
    var exclusiveModules: Set<String> {
        switch self {
            case .macOS: ["AppKit", "Carbon", "Cocoa", "Quartz", "ScreenCaptureKit", "ServiceManagement"]
            case .iOS:
                [
                    "CarPlay", "CoreLocationUI", "CoreNFC", "EventKitUI", "HealthKitUI", "HomeKit", "MessageUI",
                    "UIKit",
                    "WatchConnectivity"
                ]
        }
    }

    /// The platform the probes of a file that imports `imports` resolve against, in a project that declares
    /// `declared`, empty when it declares none or is not known. The imports decide when they name one platform's own
    /// frameworks and not the other's; otherwise the project does, and a project that declares iOS without macOS is
    /// an iOS project; otherwise the Mac, whose SDK resolves platform-neutral code as well as any. `declared` is read
    /// only when the imports do not decide, since finding it reads the project's manifests.
    public static func forFile(
        importing imports: [String], inProjectDeclaring declared: @autoclosure () -> Set<SDKPlatform>
    ) -> SDKPlatform {
        let named = allCases.filter { platform in imports.contains { platform.exclusiveModules.contains($0) } }
        if named.count == 1, let platform = named.first { return platform }
        let project = declared()
        return project.contains(.iOS) && !project.contains(.macOS) ? .iOS : .macOS
    }

    /// The modules a probe on this platform imports: the platform's defaults, then `fileImports` less the other
    /// platform's own frameworks, which this SDK lacks; sorted, unique, and at most `limit`. The defaults come first so
    /// that a file with many imports, `import UIKit` among its last, cannot crowd its platform's frameworks out.
    func probeImports(fileImports: [String], limit: Int) -> [String] {
        let foreign = Set(Self.allCases.filter { $0 != self }.flatMap(\.exclusiveModules))
        var modules: [String] = []
        for module in defaultImports + fileImports where modules.count < limit {
            guard !foreign.contains(module), !modules.contains(module) else { continue }
            modules.append(module)
        }
        return modules.sorted()
    }

    /// The `-target` a probe compiles for against this platform's SDK at `sdkVersion`: the SDK's own version, so every
    /// API it declares is available, on the host's architecture. Nil for the Mac, whose default the server keeps.
    func targetTriple(sdkVersion: String) -> String? {
        switch self {
            case .macOS: nil
            case .iOS: "\(Self.hostArchitecture)-apple-ios\(sdkVersion)-simulator"
        }
    }

    private static var hostArchitecture: String {
        #if arch(arm64)
            "arm64"
        #else
            "x86_64"
        #endif
    }
}

/// An installed SDK, as `xcrun` reports it.
public struct SDKLocation: Sendable, Equatable {
    /// The SDK's absolute path.
    public let path: String
    /// The SDK's version, such as `26.5`.
    public let version: String

    public init(path: String, version: String) {
        self.path = path
        self.version = version
    }

    private static let logger = Logger(subsystem: "Atelier.LSP", category: "SDKLocation")

    /// `platform`'s SDK, from `xcrun --sdk <name> --show-sdk-path` and `--show-sdk-version` run through `runner`; nil
    /// when either fails or prints no path and version, as with only the command-line tools installed, which carry
    /// the Mac's SDK alone.
    public static func locate(_ platform: SDKPlatform, runner: any ProcessRunner) async -> SDKLocation? {
        func show(_ property: String) async -> String? {
            let spec = ProcessSpec(
                executable: URL(filePath: "/usr/bin/xcrun"),
                arguments: ["--sdk", platform.sdkName, "--show-sdk-\(property)"],
                timeout: .seconds(30))
            do {
                let output = try await runner.run(spec)
                guard output.succeeded else {
                    logger.info(
                        "xcrun found no \(platform.sdkName, privacy: .public) SDK: \(output.errorText, privacy: .public)"
                    )
                    return nil
                }
                return String(decoding: output.standardOutput, as: UTF8.self)
            } catch {
                let reason = String(describing: error)
                logger.error(
                    "xcrun could not run for the \(platform.sdkName, privacy: .public) SDK: \(reason, privacy: .public)"
                )
                return nil
            }
        }
        guard let path = await show("path"), let version = await show("version") else { return nil }
        return SDKLocation(xcrunPath: path, version: version)
    }

    /// The location `xcrun` printed; nil unless `path` is an absolute path and `version` is dotted numbers, since the
    /// version goes into a compiler flag.
    init?(xcrunPath path: String, version: String) {
        let path = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let version = version.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = version.split(separator: ".", omittingEmptySubsequences: false)
        guard path.hasPrefix("/"), !components.isEmpty,
            components.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } })
        else { return nil }
        self.init(path: path, version: version)
    }
}

/// The platforms a project declares, read as text from its manifests: a package's `Package.swift` and an Xcode
/// project's `project.pbxproj`. Nothing in them runs, and nothing read from them reaches the server but the choice of
/// one of Apple's SDKs.
enum ProjectPlatforms {
    /// The largest manifest read; a larger one declares nothing here.
    static let maximumManifestSize = 16 << 20

    private static let logger = Logger(subsystem: "Atelier.LSP", category: "ProjectPlatforms")

    /// The platforms whose supported-platform constructor, such as `.iOS(.v17)`, `Package.swift`'s `text` calls.
    static func declared(inPackageManifest text: String) -> Set<SDKPlatform> {
        var platforms: Set<SDKPlatform> = []
        for match in text.matches(of: /\.(iOS|macCatalyst|macOS)\s*\(/) {
            // Mac Catalyst builds against the iOS SDK's frameworks.
            platforms.insert(match.output.1 == "macOS" ? .macOS : .iOS)
        }
        return platforms
    }

    /// The platforms an Xcode project's `project.pbxproj` names in its `SDKROOT` and `SUPPORTED_PLATFORMS` settings.
    static func declared(inXcodeProject contents: Data) -> Set<SDKPlatform> {
        var platforms: Set<SDKPlatform> = []
        for key in ["SDKROOT", "SUPPORTED_PLATFORMS"] {
            for value in settingValues(of: key, in: contents) {
                for sdk in value.split(separator: " ") {
                    switch sdk {
                        case "iphoneos", "iphonesimulator": platforms.insert(.iOS)
                        case "macosx": platforms.insert(.macOS)
                        default: break
                    }
                }
            }
        }
        return platforms
    }

    /// Every value of a `key = value;` or `key = "value";` setting in a property-list text, such as a `project.pbxproj`.
    private static func settingValues(of key: String, in contents: Data) -> [String] {
        let needle = Data(key.utf8)
        var values: [String] = []
        var searchStart = contents.startIndex
        while let found = contents.range(of: needle, in: searchStart ..< contents.endIndex) {
            searchStart = found.upperBound
            // A longer name that merely ends with the key, as `MY_SDKROOT`, is another setting.
            if found.lowerBound > contents.startIndex, isNameByte(contents[found.lowerBound - 1]) { continue }
            var index = found.upperBound
            while index < contents.endIndex, contents[index] == UInt8(ascii: " ") { index += 1 }
            guard index < contents.endIndex, contents[index] == UInt8(ascii: "=") else { continue }
            index += 1
            while index < contents.endIndex, contents[index] == UInt8(ascii: " ") { index += 1 }
            let quoted = index < contents.endIndex && contents[index] == UInt8(ascii: "\"")
            if quoted { index += 1 }
            let terminator = quoted ? UInt8(ascii: "\"") : UInt8(ascii: ";")
            let start = index
            while index < contents.endIndex, contents[index] != terminator, contents[index] != UInt8(ascii: "\n") {
                index += 1
            }
            values.append(String(decoding: contents[start ..< index], as: UTF8.self))
        }
        return values
    }

    private static func isNameByte(_ byte: UInt8) -> Bool {
        switch byte {
            case UInt8(ascii: "a") ... UInt8(ascii: "z"), UInt8(ascii: "A") ... UInt8(ascii: "Z"),
                UInt8(ascii: "0") ... UInt8(ascii: "9"), UInt8(ascii: "_"):
                true
            default:
                false
        }
    }

    /// The platforms the nearest project that declares any, above the file at `fileURL`, declares: `read` gives what a
    /// directory's own manifests declare, ``declared(inDirectory:)`` or a memo of it, for each directory from the file's
    /// own up to the repository's root, the first directory that holds a `.git`. Empty when none declares a platform.
    static func declared(
        forFileAt fileURL: URL, reading read: (String) -> Set<SDKPlatform> = declared(inDirectory:)
    ) -> Set<SDKPlatform> {
        var directory = fileURL.deletingLastPathComponent().standardizedFileURL.path(percentEncoded: false)
        while true {
            let platforms = read(directory)
            if !platforms.isEmpty { return platforms }
            let parent = (directory as NSString).deletingLastPathComponent
            guard !FileManager.default.fileExists(atPath: (directory as NSString).appendingPathComponent(".git")),
                !parent.isEmpty, parent != directory
            else { return [] }
            directory = parent
        }
    }

    /// The platforms the manifests directly in `directory` declare.
    static func declared(inDirectory directory: String) -> Set<SDKPlatform> {
        var platforms: Set<SDKPlatform> = []
        if let manifest = readManifest(atPath: (directory as NSString).appendingPathComponent("Package.swift")) {
            platforms.formUnion(declared(inPackageManifest: String(decoding: manifest, as: UTF8.self)))
        }
        let entries: [String]
        do {
            entries = try FileManager.default.contentsOfDirectory(atPath: directory)
        } catch {
            logger.debug("No manifests read in a directory: \(String(describing: error), privacy: .private)")
            return platforms
        }
        for entry in entries where entry.hasSuffix(".xcodeproj") {
            let path = ((directory as NSString).appendingPathComponent(entry) as NSString)
                .appendingPathComponent("project.pbxproj")
            if let project = readManifest(atPath: path) { platforms.formUnion(declared(inXcodeProject: project)) }
        }
        return platforms
    }

    /// The contents of the regular file at `path`; nil when there is none, when it is not a regular file, or when it is
    /// larger than ``maximumManifestSize``. Checked before it is opened, so that opening a device named like a manifest
    /// has no effect, then opened without blocking and checked again on its descriptor, so that a pipe swapped in
    /// meanwhile cannot stall the read.
    static func readManifest(atPath path: String) -> Data? {
        var named = stat()
        guard stat(path, &named) == 0, named.st_mode & S_IFMT == S_IFREG else { return nil }
        let descriptor = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        var status = stat()
        guard fstat(descriptor, &status) == 0, status.st_mode & S_IFMT == S_IFREG,
            status.st_size <= off_t(maximumManifestSize)
        else { return nil }
        do {
            return try handle.read(upToCount: maximumManifestSize) ?? Data()
        } catch {
            logger.info("A project manifest could not be read: \(String(describing: error), privacy: .private)")
            return nil
        }
    }
}
